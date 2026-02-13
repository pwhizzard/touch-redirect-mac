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

/// Digitizer usage page / Touch Screen usage for HID matching
private let kDigitizerUsagePage: Int = 0x0D
private let kTouchScreenUsage: Int = 0x04

// MARK: - Connected Device Entry

/// Tracks a single connected HID touch device with its resolved profile
struct ConnectedTouchDevice {
    let device: IOHIDDevice
    let identity: TouchDeviceIdentity
    let profile: TouchDeviceProfile
    let productName: String
    let manufacturer: String
    var reportCount: Int = 0
}

class HIDManager {
    private var manager: IOHIDManager!
    private weak var appDelegate: AppDelegate?
    private let touchParser = TouchParser()

    /// Registry of all currently connected touch devices, keyed by stable identity
    private(set) var connectedDevices: [TouchDeviceIdentity: ConnectedTouchDevice] = [:]

    /// Report buffers keyed by device identity (must stay allocated while device is connected).
    /// Array-per-identity because devices like the Xeneon expose multiple HID interfaces that
    /// each need their own callback buffer.
    private var reportBuffers: [TouchDeviceIdentity: [UnsafeMutablePointer<UInt8>]] = [:]

    /// Maps every registered IOHIDDevice interface reference to its owning TouchDeviceIdentity.
    /// This is the authoritative lookup for incoming HID reports — allows reports from any
    /// interface (primary, additional digitizer, companion Mouse) to be attributed correctly.
    private var interfaceToIdentity: [IOHIDDevice: TouchDeviceIdentity] = [:]

    /// Tracks all IOHIDDevice interface references belonging to each identity, for cleanup.
    private var identityInterfaces: [TouchDeviceIdentity: [IOHIDDevice]] = [:]

    // Parsed touch report callback (source-aware: report now carries deviceIdentity + profileID)
    var onTouchReport: ((_ report: TouchReport) -> Void)?

    /// Callback when the set of connected devices changes
    var onDeviceRegistryChanged: (() -> Void)?

    /// Returns true if at least one touch device is currently connected
    var isDeviceConnected: Bool {
        return !connectedDevices.isEmpty
    }

    /// Returns the identities of all currently connected touch devices
    var connectedDeviceIdentities: [TouchDeviceIdentity] {
        return Array(connectedDevices.keys)
    }

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        setupHIDManager()

        // Listen for UI requests to re-broadcast the device list (e.g. Settings opened)
        NotificationCenter.default.addObserver(
            forName: .requestDeviceListBroadcast,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.broadcastDeviceList()
        }
    }

    // MARK: - Setup

    private func setupHIDManager() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        logError("═══ HID Manager Setup (multi-device) ═══")

        // Build matching dictionaries for all known profiles + a broad digitizer catch-all.
        // This ensures we see both known VID/PID pairs and any new touch device.
        var matchingDicts: [[String: Any]] = []

        for profile in TouchDeviceProfile.allKnown {
            for pair in profile.vendorProductPairs {
                matchingDicts.append([
                    kIOHIDVendorIDKey as String: pair.vendorID,
                    kIOHIDProductIDKey as String: pair.productID
                ])
                logError("Matching: \(profile.displayName) VID=0x\(String(pair.vendorID, radix: 16)) PID=0x\(String(pair.productID, radix: 16))")
            }
        }

        // Broad digitizer/touch screen matcher (catches unknown touch devices)
        matchingDicts.append([
            kIOHIDDeviceUsagePageKey as String: kDigitizerUsagePage,
            kIOHIDDeviceUsageKey as String: kTouchScreenUsage
        ])

        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDicts as CFArray)
        logError("Device matching criteria set (\(matchingDicts.count) matchers)")

        // Register callbacks
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
            logError("Failed to open HID Manager: IOReturn=\(result) (\(ioReturnDescription(result)))")
            logError("   This usually means Input Monitoring permission is missing.")
            logError("   Go to: System Settings → Privacy & Security → Input Monitoring")
        } else {
            logError("HID Manager opened successfully")

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

    // MARK: - Device Connection

    private func deviceConnected(_ device: IOHIDDevice) {
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

        // Accept touch screen interfaces and companion interfaces (e.g. Mouse on Xeneon)
        let isDigitizer = TouchDeviceProfileResolver.isTouchDigitizer(usagePage: usagePage, usage: usage)
        let isCompanion = TouchDeviceProfileResolver.isCompanionInterface(
            usagePage: usagePage, usage: usage, vendorID: vendorID, productID: productID
        )

        guard isDigitizer || isCompanion else {
            logError("  Not a touch or companion interface — skipping")
            logError("═══════════════════════════")
            return
        }

        if isDigitizer {
            logError("  This IS a touch screen interface!")
        } else {
            logError("  This is a companion Mouse interface for a known touch device — seizing to take full control")
        }

        // Resolve profile
        let profile = TouchDeviceProfileResolver.resolve(
            vendorID: vendorID,
            productID: productID,
            productName: product,
            manufacturer: manufacturer
        )
        logError("  Resolved profile: \(profile.displayName) (\(profile.id.rawValue))")

        // Build stable identity
        let identity = TouchDeviceIdentity(
            vendorID: vendorID,
            productID: productID,
            locationID: locationID
        )

        // Open the device
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if openResult == kIOReturnSuccess {
            logError("  Device opened successfully (exclusive/seized)")
        } else {
            logError("  Failed to seize device, trying shared open...")
            let normalOpen = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            if normalOpen == kIOReturnSuccess {
                logError("  Device opened successfully (shared access)")
            } else {
                logError("  Failed to open device: IOReturn=\(normalOpen) (\(ioReturnDescription(normalOpen)))")
                logError("═══════════════════════════")
                return
            }
        }

        // Some devices (e.g. Corsair XENEON EDGE) expose multiple HID interfaces
        // with the same VID/PID/LocationID. Register input report callbacks for ALL
        // matching touch interfaces so we catch the one that actually sends data.
        if connectedDevices[identity] != nil {
            logError("  Additional interface for already-registered device — registering input callback")
            registerInputReportCallback(device, identity: identity, profile: profile)
            logError("═══════════════════════════")
            return
        }

        // Register in device registry (first interface for this identity)
        let entry = ConnectedTouchDevice(
            device: device,
            identity: identity,
            profile: profile,
            productName: product,
            manufacturer: manufacturer
        )
        connectedDevices[identity] = entry

        // Register input report callback for this device
        registerInputReportCallback(device, identity: identity, profile: profile)

        // Notify app
        appDelegate?.updateStatus(connected: true)
        onDeviceRegistryChanged?()
        broadcastDeviceList()
        ScreenManager.shared.refreshTargetScreen(reason: "touch device connected: \(profile.displayName)")
        logError("  Registry now has \(connectedDevices.count) device(s)")
        logError("═══════════════════════════")
    }

    // MARK: - Device Disconnection

    private func deviceDisconnected(_ device: IOHIDDevice) {
        // Resolve identity from the interface map (works for any interface, not just primary)
        guard let identity = interfaceToIdentity.removeValue(forKey: device) else {
            logError("Unknown interface disconnected — not in interface map")
            return
        }

        // Remove this interface from the identity's interface list
        identityInterfaces[identity]?.removeAll { $0 === device }
        let remainingInterfaces = identityInterfaces[identity]?.count ?? 0
        logError("Interface disconnected for \(connectedDevices[identity]?.profile.displayName ?? "?") (\(identity)), \(remainingInterfaces) interface(s) remaining")

        // Only remove the full device entry when ALL its interfaces have disconnected
        if remainingInterfaces == 0 {
            identityInterfaces.removeValue(forKey: identity)
            let entry = connectedDevices.removeValue(forKey: identity)
            logError("All interfaces gone — removing device: \(entry?.profile.displayName ?? "Unknown") (\(identity))")

            // Free all report buffers for this device identity
            if let buffers = reportBuffers.removeValue(forKey: identity) {
                for buffer in buffers {
                    buffer.deallocate()
                }
            }
        }

        let stillConnected = !connectedDevices.isEmpty
        appDelegate?.updateStatus(connected: stillConnected)
        onDeviceRegistryChanged?()
        broadcastDeviceList()
        ScreenManager.shared.refreshTargetScreen(reason: "touch device disconnected")
    }

    /// Post a notification with the current list of connected device descriptors for UI consumption.
    /// Public so that Settings UI can request a fresh list on appear.
    func broadcastDeviceList() {
        let descriptors: [ConnectedDeviceDescriptor] = connectedDevices.map { (identity, entry) in
            ConnectedDeviceDescriptor(
                id: identity.persistenceKey,
                profileName: entry.profile.displayName,
                shortIdentity: identity.description,
                profileID: entry.profile.id
            )
        }
        NotificationCenter.default.post(
            name: .connectedTouchDevicesChanged,
            object: nil,
            userInfo: ["devices": descriptors]
        )
    }

    // MARK: - Input Report Handling

    private func registerInputReportCallback(_ device: IOHIDDevice, identity: TouchDeviceIdentity, profile: TouchDeviceProfile) {
        // Register interface ownership BEFORE wiring the callback so that
        // the very first report can be resolved to the correct identity.
        interfaceToIdentity[device] = identity
        identityInterfaces[identity, default: []].append(device)

        let reportSize = max(64, profile.expectedReportSize)
        let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportSize)
        // Append to the array — each HID interface gets its own buffer
        reportBuffers[identity, default: []].append(reportBuffer)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        IOHIDDeviceRegisterInputReportCallback(
            device,
            reportBuffer,
            reportSize,
            { context, result, sender, type, reportID, report, reportLength in
                guard let context = context else { return }
                let this = Unmanaged<HIDManager>.fromOpaque(context).takeUnretainedValue()

                let data = Array(UnsafeBufferPointer(start: report, count: reportLength))
                // sender is the IOHIDDevice pointer passed as UnsafeMutableRawPointer
                guard let senderPtr = sender else { return }
                let hidDevice = Unmanaged<IOHIDDevice>.fromOpaque(senderPtr).takeUnretainedValue()
                this.handleInputReport(reportID: reportID, data: data, senderDevice: hidDevice)
            },
            selfPtr
        )

        log("Input report callback registered for \(profile.displayName) (\(identity)) [interfaces: \(identityInterfaces[identity]?.count ?? 0)]")
    }

    /// Counter for dropped reports (unknown sender) — should always be zero after fix.
    private var droppedReportCount: Int = 0

    private func handleInputReport(reportID: UInt32, data: [UInt8], senderDevice: IOHIDDevice) {
        // Resolve identity via the interface map (works for ALL registered interfaces:
        // primary, additional digitizer, companion Mouse, etc.)
        guard let identity = interfaceToIdentity[senderDevice],
              let entry = connectedDevices[identity] else {
            droppedReportCount += 1
            if droppedReportCount <= 5 || droppedReportCount % 100 == 0 {
                logError("⚠️ Dropped HID report #\(droppedReportCount) from unknown sender interface")
            }
            return
        }

        // Increment report count for diagnostics (read-modify-write for value type)
        var updatedEntry = connectedDevices[identity]!
        updatedEntry.reportCount += 1
        connectedDevices[identity] = updatedEntry
        let count = updatedEntry.reportCount

        // Log first few reports and then periodically (debug builds)
        if count <= 5 || count % 100 == 0 {
            log("HID Report #\(count) [\(entry.profile.displayName)]: ID=0x\(String(reportID, radix: 16)), \(data.count) bytes: \(data.prefix(10).map { String(format: "%02X", $0) }.joined(separator: " "))")
        }

        // Check if this report ID is a touch report for this device's profile.
        // Empty touchReportIDs means "accept any report ID" (for unknown/new devices).
        let acceptedIDs = entry.profile.touchReportIDs
        if acceptedIDs.isEmpty || acceptedIDs.contains(reportID) {
            if let report = touchParser.parse(data: data, profile: entry.profile, deviceIdentity: identity) {
                onTouchReport?(report)
            }
        }
    }

    deinit {
        // Free all report buffers (array-per-identity)
        for (_, buffers) in reportBuffers {
            for buffer in buffers {
                buffer.deallocate()
            }
        }
        reportBuffers.removeAll()
        interfaceToIdentity.removeAll()
        identityInterfaces.removeAll()

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
