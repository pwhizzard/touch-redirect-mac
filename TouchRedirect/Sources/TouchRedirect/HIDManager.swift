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
        
        log("Looking for device: VendorID=0x\(String(kVendorID, radix: 16)), ProductID=0x\(String(kProductID, radix: 16)), UsagePage=0x\(String(kUsagePage, radix: 16))")
        
        // Set device matching criteria - try matching without usage page first
        // Some devices have multiple interfaces, and we want the touch one
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: kVendorID,
            kIOHIDProductIDKey as String: kProductID
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        log("Device matching criteria set")
        
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
            logError("Failed to open HID Manager: \(result)")
        } else {
            log("HID Manager opened successfully, waiting for device...")
        }
    }
    
    private func deviceConnected(_ device: IOHIDDevice) {
        // Get device info for logging
        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        
        log("Device connected: \(product)")
        log("  VendorID: 0x\(String(vendorID, radix: 16)), ProductID: 0x\(String(productID, radix: 16))")
        log("  UsagePage: 0x\(String(usagePage, radix: 16)), Usage: 0x\(String(usage, radix: 16))")
        
        // Only use touch screen interface (UsagePage 0x0D, Usage 0x04)
        if usagePage == kUsagePage && usage == kUsage {
            log("✓ This is the touch screen interface")
            
            // Try to open the device explicitly
            let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            if openResult == kIOReturnSuccess {
                log("  Device opened successfully (seized)")
            } else {
                log("  Failed to seize device (\(openResult)), trying normal open...")
                let normalOpen = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
                if normalOpen == kIOReturnSuccess {
                    log("  Device opened successfully (normal)")
                } else {
                    log("  ⚠️ Failed to open device: \(normalOpen)")
                }
            }
            
            currentDevice = device
            appDelegate?.updateStatus(connected: true)
            registerInputReportCallback(device)
            ScreenManager.shared.refreshTargetScreen(reason: "touch device connected")
        } else {
            log("  (Skipping - not the touch interface)")
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
}
