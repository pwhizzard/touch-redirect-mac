//
//  HIDManager.swift
//  TouchRedirect
//
//  Copyright (C) 2026 Touch Redirect contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
//  Manages USB HID device detection and communication with touch-enabled displays.
//  Handles device matching, connection callbacks, and raw touch report parsing.
//

import Foundation
import IOKit
import IOKit.hid

// MARK: - HID Device Identifiers

// WebEx Desk Pro HID identifiers (can be extended for other devices)
private let kVendorID: Int = 0x05a6   // Cisco Systems, Inc.
private let kProductID: Int = 0x0b05  // Desk Pro HID Device
private let kUsagePage: Int = 0x0D    // Digitizer
private let kUsage: Int = 0x04        // Touch Screen

class HIDManager {
    private var manager: IOHIDManager!
    private weak var appDelegate: AppDelegate?
    private var currentDevice: IOHIDDevice?
    private let touchParser = TouchParser()
    
    // Parsed touch report callback
    var onTouchReport: ((_ report: TouchReport) -> Void)?
    
    /// Returns true if a touch device is currently connected
    var isDeviceConnected: Bool {
        return currentDevice != nil
    }
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        setupHIDManager()
    }
    
    private func setupHIDManager() {
        // Create HID Manager
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        logError("═══ HID Manager Setup ═══")
        logError("Looking for device: VendorID=0x\(String(kVendorID, radix: 16)), ProductID=0x\(String(kProductID, radix: 16)), UsagePage=0x\(String(kUsagePage, radix: 16))")
        
        // Set device matching criteria - try matching without usage page first
        // Some devices have multiple interfaces, and we want the touch one
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: kVendorID,
            kIOHIDProductIDKey as String: kProductID
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        logError("Device matching criteria set (VendorID & ProductID only)")
        
        // Register callbacks using the proper pattern with retained self
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let this = Unmanaged<HIDManager>.fromOpaque(context).takeUnretainedValue()
            this.deviceConnected(device)
        }, selfPtr)
        
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let this = Unmanaged<HIDManager>.fromOpaque(context).takeUnretainedValue()
            this.deviceDisconnected(device)
        }, selfPtr)
        
        // Schedule with run loop using commonModes so HID events work even when menus are open
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        
        // Open manager
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            logError("❌ Failed to open HID Manager: IOReturn=\(result) (\(ioReturnDescription(result)))")
            logError("   This usually means Input Monitoring permission is missing.")
            logError("   Go to: System Settings → Privacy & Security → Input Monitoring")
        } else {
            logError("✓ HID Manager opened successfully")
            
            // Enumerate already-connected devices
            if let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
                logError("Found \(deviceSet.count) already-connected HID device(s)")
                for device in deviceSet {
                    let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
                    let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
                    log("  - VID=0x\(String(vid, radix: 16)) PID=0x\(String(pid, radix: 16))")
                }
            } else {
                logError("No HID devices found at startup (waiting for connection...)")
            }
        }
        logError("═══════════════════════════")
    }
    
    private func deviceConnected(_ device: IOHIDDevice) {
        // Get device info for logging
        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        let manufacturer = IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String ?? "Unknown"
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        let locationID = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
        
        logError("═══ Device Connected ═══")
        logError("Product:      \(product)")
        logError("Manufacturer: \(manufacturer)")
        logError("VendorID:     0x\(String(vendorID, radix: 16))")
        logError("ProductID:    0x\(String(productID, radix: 16))")
        logError("UsagePage:    0x\(String(usagePage, radix: 16)) (\(usagePageName(usagePage)))")
        logError("Usage:        0x\(String(usage, radix: 16)) (\(usageName(usage)))")
        logError("LocationID:   0x\(String(locationID, radix: 16))")
        
        // Only use touch screen interface (UsagePage 0x0D, Usage 0x04)
        if usagePage == kUsagePage && usage == kUsage {
            logError("✓ This IS the touch screen interface!")
            
            // Try to open the device explicitly
            let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            if openResult == kIOReturnSuccess {
                logError("✓ Device opened successfully (exclusive/seized)")
            } else {
                logError("⚠️  Failed to seize device: IOReturn=\(openResult) (\(ioReturnDescription(openResult)))")
                logError("   Trying normal (shared) open...")
                let normalOpen = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
                if normalOpen == kIOReturnSuccess {
                    logError("✓ Device opened successfully (shared access)")
                } else {
                    logError("❌ Failed to open device: IOReturn=\(normalOpen) (\(ioReturnDescription(normalOpen)))")
                    logError("   Device may be in use by another process (WebexHelper, UPPD)")
                    logError("   Try: killall WebexHelper")
                    logError("═══════════════════════════")
                    return
                }
            }
            
            currentDevice = device
            appDelegate?.updateStatus(connected: true)
            registerInputReportCallback(device)
            ScreenManager.shared.refreshTargetScreen(reason: "touch device connected")
            logError("═══════════════════════════")
        } else {
            logError("⚠️  NOT the touch interface (wrong UsagePage/Usage)")
            logError("   Expected: UsagePage=0x0D (Digitizer), Usage=0x04 (Touch Screen)")
            logError("   Got:      UsagePage=0x\(String(usagePage, radix: 16)), Usage=0x\(String(usage, radix: 16))")
            logError("   Skipping this interface...")
            logError("═══════════════════════════")
        }
    }
    
    private func deviceDisconnected(_ device: IOHIDDevice) {
        log("WebEx Desk Pro disconnected!")
        currentDevice = nil
        appDelegate?.updateStatus(connected: false)
        ScreenManager.shared.refreshTargetScreen(reason: "touch device disconnected")
    }
    
    private func registerInputReportCallback(_ device: IOHIDDevice) {
        // Allocate buffer for input reports (max touch report is typically < 64 bytes)
        let reportSize = 64
        let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportSize)
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        IOHIDDeviceRegisterInputReportCallback(
            device,
            reportBuffer,
            reportSize,
            { context, result, sender, type, reportID, report, reportLength in
                guard let context = context else { return }
                let this = Unmanaged<HIDManager>.fromOpaque(context).takeUnretainedValue()
                
                // Convert to byte array
                let data = Array(UnsafeBufferPointer(start: report, count: reportLength))
                this.handleInputReport(reportID: reportID, data: data)
            },
            selfPtr
        )
        
        log("Input report callback registered")
    }
    
    private var reportCount = 0
    
    private func handleInputReport(reportID: UInt32, data: [UInt8]) {
        reportCount += 1
        
        // Log first few reports and then periodically
        if reportCount <= 5 || reportCount % 100 == 0 {
            log("HID Report #\(reportCount): ID=0x\(String(reportID, radix: 16)), \(data.count) bytes: \(data.prefix(10).map { String(format: "%02X", $0) }.joined(separator: " "))")
        }
        
        // Report ID 0x04 is touch data
        if reportID == 0x04 {
            if let report = touchParser.parse(data: data) {
                onTouchReport?(report)
            }
        }
    }
    
    deinit {
        if manager != nil {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
    
    // MARK: - Helper Functions
    
    private func ioReturnDescription(_ code: IOReturn) -> String {
        switch code {
        case kIOReturnSuccess:
            return "Success"
        case kIOReturnError:
            return "General Error"
        case kIOReturnNoMemory:
            return "No Memory"
        case kIOReturnNoResources:
            return "No Resources"
        case kIOReturnIPCError:
            return "IPC Error"
        case kIOReturnNoDevice:
            return "No Device"
        case kIOReturnNotPrivileged:
            return "Not Privileged (Permission Denied)"
        case kIOReturnBadArgument:
            return "Bad Argument"
        case kIOReturnLockedRead:
            return "Locked Read"
        case kIOReturnLockedWrite:
            return "Locked Write"
        case kIOReturnExclusiveAccess:
            return "Exclusive Access (Device in use by another process)"
        case kIOReturnBadMessageID:
            return "Bad Message ID"
        case kIOReturnUnsupported:
            return "Unsupported"
        case kIOReturnVMError:
            return "VM Error"
        case kIOReturnInternalError:
            return "Internal Error"
        case kIOReturnIOError:
            return "IO Error"
        case kIOReturnCannotLock:
            return "Cannot Lock"
        case kIOReturnNotOpen:
            return "Not Open"
        case kIOReturnNotReadable:
            return "Not Readable"
        case kIOReturnNotWritable:
            return "Not Writable"
        case kIOReturnNotAligned:
            return "Not Aligned"
        case kIOReturnBadMedia:
            return "Bad Media"
        case kIOReturnStillOpen:
            return "Still Open"
        case kIOReturnRLDError:
            return "RLD Error"
        case kIOReturnDMAError:
            return "DMA Error"
        case kIOReturnBusy:
            return "Busy"
        case kIOReturnTimeout:
            return "Timeout"
        case kIOReturnOffline:
            return "Offline"
        case kIOReturnNotReady:
            return "Not Ready"
        case kIOReturnNotAttached:
            return "Not Attached"
        case kIOReturnNoChannels:
            return "No Channels"
        case kIOReturnNoSpace:
            return "No Space"
        case kIOReturnPortExists:
            return "Port Exists"
        case kIOReturnCannotWire:
            return "Cannot Wire"
        case kIOReturnNoInterrupt:
            return "No Interrupt"
        case kIOReturnNoFrames:
            return "No Frames"
        case kIOReturnMessageTooLarge:
            return "Message Too Large"
        case kIOReturnNotPermitted:
            return "Not Permitted"
        case kIOReturnNoPower:
            return "No Power"
        case kIOReturnNoMedia:
            return "No Media"
        case kIOReturnUnformattedMedia:
            return "Unformatted Media"
        case kIOReturnUnsupportedMode:
            return "Unsupported Mode"
        case kIOReturnUnderrun:
            return "Underrun"
        case kIOReturnOverrun:
            return "Overrun"
        case kIOReturnDeviceError:
            return "Device Error"
        case kIOReturnNoCompletion:
            return "No Completion"
        case kIOReturnAborted:
            return "Aborted"
        case kIOReturnNoBandwidth:
            return "No Bandwidth"
        case kIOReturnNotResponding:
            return "Not Responding"
        case kIOReturnIsoTooOld:
            return "Iso Too Old"
        case kIOReturnIsoTooNew:
            return "Iso Too New"
        case kIOReturnNotFound:
            return "Not Found"
        default:
            return "Unknown Error Code: \(code)"
        }
    }
    
    private func usagePageName(_ usagePage: Int) -> String {
        switch usagePage {
        case 0x01:
            return "Generic Desktop"
        case 0x0D:
            return "Digitizer"
        case 0x0C:
            return "Consumer"
        case 0x09:
            return "Button"
        case 0x07:
            return "Keyboard"
        case 0x08:
            return "LED"
        default:
            return "Unknown"
        }
    }
    
    private func usageName(_ usage: Int) -> String {
        switch usage {
        case 0x01:
            return "Pointer"
        case 0x02:
            return "Mouse"
        case 0x04:
            return "Touch Screen"
        case 0x05:
            return "Touch Pad"
        case 0x06:
            return "Keyboard"
        default:
            return "Unknown"
        }
    }
}
