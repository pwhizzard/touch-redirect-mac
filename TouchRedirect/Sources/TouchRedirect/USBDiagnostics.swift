//
//  USBDiagnostics.swift
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
//  USB HID device diagnostics tool for troubleshooting device detection issues

import Foundation
import IOKit
import IOKit.hid
import AppKit

class USBDiagnostics {
    
    // MARK: - Device Information
    
    struct HIDDeviceInfo {
        let vendorID: Int
        let productID: Int
        let product: String
        let manufacturer: String
        let usagePage: Int
        let usage: Int
        let interfaceID: Int?
        let locationID: Int?

        var isWebExDeskPro: Bool {
            return vendorID == 0x05a6 && productID == 0x0b05
        }

        var isTouchInterface: Bool {
            return TouchDeviceProfileResolver.isTouchDigitizer(usagePage: usagePage, usage: usage)
        }

        /// Resolved device profile using the central resolver
        var resolvedProfile: TouchDeviceProfile {
            return TouchDeviceProfileResolver.resolve(
                vendorID: vendorID,
                productID: productID,
                productName: product,
                manufacturer: manufacturer
            )
        }

        /// Whether this device matches a known (non-unknown) profile
        var isKnownDevice: Bool {
            return resolvedProfile.id != .unknown
        }
    }
    
    // MARK: - System Information
    
    struct SystemInfo {
        let macModel: String
        let osVersion: String
        let architecture: String
        let chipModel: String
    }
    
    // MARK: - Diagnostic Results
    
    struct DiagnosticResults {
        let timestamp: Date
        let systemInfo: SystemInfo
        let allHIDDevices: [HIDDeviceInfo]
        let webexDevices: [HIDDeviceInfo]
        let touchInterfaces: [HIDDeviceInfo]
        let knownDevices: [HIDDeviceInfo]
        let ioHIDAccessGranted: Bool
        let accessibilityGranted: Bool
        let conflictingProcesses: [String]
        let entitlementsPresent: [String: Bool]

        var hasCriticalIssues: Bool {
            return !ioHIDAccessGranted || !accessibilityGranted || (webexDevices.isEmpty && knownDevices.isEmpty)
        }
    }
    
    // MARK: - Public API
    
    /// Run full diagnostics and return structured results
    static func runDiagnostics() -> DiagnosticResults {
        let systemInfo = gatherSystemInfo()
        let allDevices = enumerateAllHIDDevices()
        let webexDevices = allDevices.filter { $0.isWebExDeskPro }
        let touchInterfaces = webexDevices.filter { $0.isTouchInterface }
        let knownDevices = allDevices.filter { $0.isKnownDevice && $0.isTouchInterface }
        let ioHIDAccess = checkIOHIDAccess()
        let accessibilityAccess = AXIsProcessTrusted()
        let conflicts = findConflictingProcesses()
        let entitlements = checkEntitlements()

        return DiagnosticResults(
            timestamp: Date(),
            systemInfo: systemInfo,
            allHIDDevices: allDevices,
            webexDevices: webexDevices,
            touchInterfaces: touchInterfaces,
            knownDevices: knownDevices,
            ioHIDAccessGranted: ioHIDAccess,
            accessibilityGranted: accessibilityAccess,
            conflictingProcesses: conflicts,
            entitlementsPresent: entitlements
        )
    }
    
    /// Generate formatted diagnostic report
    static func generateReport() -> String {
        let results = runDiagnostics()
        var report = """
        ═══════════════════════════════════════════════════════════
        TouchRedirect USB Diagnostics Report
        ═══════════════════════════════════════════════════════════
        Generated: \(ISO8601DateFormatter().string(from: results.timestamp))
        
        """
        
        // System Information
        report += """
        
        ┌─────────────────────────────────────────────────────────┐
        │ SYSTEM INFORMATION                                      │
        └─────────────────────────────────────────────────────────┘
        
        Mac Model:      \(results.systemInfo.macModel)
        Chip:           \(results.systemInfo.chipModel)
        Architecture:   \(results.systemInfo.architecture)
        macOS Version:  \(results.systemInfo.osVersion)
        
        """
        
        // Permission Status
        report += """
        
        ┌─────────────────────────────────────────────────────────┐
        │ PERMISSION STATUS                                       │
        └─────────────────────────────────────────────────────────┘
        
        """
        report += formatStatus("IOKit HID Access", results.ioHIDAccessGranted)
        report += formatStatus("Accessibility", results.accessibilityGranted)
        
        // Entitlements
        report += """
        
        
        ┌─────────────────────────────────────────────────────────┐
        │ APP ENTITLEMENTS                                        │
        └─────────────────────────────────────────────────────────┘
        
        """
        for (key, present) in results.entitlementsPresent.sorted(by: { $0.key < $1.key }) {
            report += formatStatus(key, present)
        }
        
        // Conflicting Processes
        report += """
        
        
        ┌─────────────────────────────────────────────────────────┐
        │ CONFLICTING PROCESSES                                   │
        └─────────────────────────────────────────────────────────┘
        
        """
        if results.conflictingProcesses.isEmpty {
            report += "  ✓ No conflicting processes detected\n"
        } else {
            report += "  ⚠️  WARNING: Found \(results.conflictingProcesses.count) conflicting process(es):\n\n"
            for process in results.conflictingProcesses {
                report += "    • \(process)\n"
            }
            report += "\n  Kill these processes with: killall <process_name>\n"
        }
        
        // Touch Device Detection (profile-aware)
        report += """
        
        
        ┌─────────────────────────────────────────────────────────┐
        │ TOUCH DEVICE DETECTION                                  │
        └─────────────────────────────────────────────────────────┘
        
        """
        if results.knownDevices.isEmpty && results.webexDevices.isEmpty {
            report += """
              No recognized touch devices detected at the USB level.
              
              General troubleshooting:
              1. Verify USB-C cable is data-capable (not charge-only)
              2. Try different USB-C ports on your Mac
              3. Check System Information -> USB for your device
              4. Kill conflicting software (UPPD, WebexHelper)
              
              Desk Pro specific:
              • Try connecting BOTH HDMI + USB-C cables
              • Power cycle the Desk Pro (unplug power, wait 30s)
              • If UPPD was previously used, HDMI + USB-C may be required
              
            """
        } else {
            let allKnown = results.knownDevices
            report += "  Found \(allKnown.count) recognized touch device interface(s)\n\n"
            for (index, device) in allKnown.enumerated() {
                let profile = device.resolvedProfile
                report += """
                  Device #\(index + 1): \(profile.displayName)
                    Product:      \(device.product)
                    Manufacturer: \(device.manufacturer)
                    VID/PID:      0x\(String(device.vendorID, radix: 16))/0x\(String(device.productID, radix: 16))
                    Usage Page:   0x\(String(device.usagePage, radix: 16)) (\(usagePageName(device.usagePage)))
                    Usage:        0x\(String(device.usage, radix: 16)) (\(usageName(device.usage)))
                    Max Touches:  \(profile.maxTouches)
                    Edge Comp:    \(profile.defaultEdgeCompensation ? "On (default)" : "Off (default)")
                
                """
            }

            // Also show any unknown touch-capable devices
            let unknownTouch = results.allHIDDevices.filter { $0.isTouchInterface && !$0.isKnownDevice }
            if !unknownTouch.isEmpty {
                report += "  Additionally found \(unknownTouch.count) unrecognized touch interface(s):\n\n"
                for (index, device) in unknownTouch.enumerated() {
                    report += """
                      Unknown #\(index + 1): \(device.product) by \(device.manufacturer)
                        VID/PID:      0x\(String(device.vendorID, radix: 16))/0x\(String(device.productID, radix: 16))
                    
                    """
                }
            }

            // Desk Pro specific note if Desk Pro detected but no touch interface
            let deskProNoTouch = results.webexDevices.filter { !$0.isTouchInterface }
            if !deskProNoTouch.isEmpty && results.touchInterfaces.isEmpty {
                report += """
                  Note: Desk Pro detected but touch digitizer interface missing.
                  Try connecting HDMI + USB-C, or check for "Enable Touch" on device.
                
                """
            }
        }

        // Touch Interface Status
        report += """
        
        ┌─────────────────────────────────────────────────────────┐
        │ TOUCH INTERFACE STATUS                                  │
        └─────────────────────────────────────────────────────────┘
        
        """
        let anyTouchReady = !results.knownDevices.isEmpty || !results.touchInterfaces.isEmpty
        if anyTouchReady {
            report += "  Touch interface detected and available!\n\n"
            if !results.ioHIDAccessGranted {
                report += """
                  However, IOKit HID permission is missing.
                     Grant Input Monitoring permission in System Settings.
                  
                """
            }
            if !results.accessibilityGranted {
                report += """
                  Accessibility permission is missing.
                     Required to inject cursor events.
                  
                """
            }
        } else {
            report += "  No touch interface available. See device detection above for details.\n"
        }
        
        // Screen Resolution Details (logical vs native)
        report += """

        ┌─────────────────────────────────────────────────────────┐
        │ SCREEN RESOLUTION DETAILS                               │
        └─────────────────────────────────────────────────────────┘
        
        """
        for screen in NSScreen.screens {
            let name = screen.localizedName
            let logicalWidth = Int(screen.frame.width)
            let logicalHeight = Int(screen.frame.height)
            let backingScale = Int(screen.backingScaleFactor)
            let nativeWidth = logicalWidth * backingScale
            let nativeHeight = logicalHeight * backingScale
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0

            report += "  \(name) (ID: \(displayID))\n"
            report += "    Logical:  \(logicalWidth) x \(logicalHeight) pts\n"
            report += "    Native:   \(nativeWidth) x \(nativeHeight) px (@\(backingScale)x)\n"
            if backingScale > 1 {
                report += "    Note:     Touch coordinates map to logical (point) space.\n"
                report += "              Calibration uses logical dimensions.\n"
            }
            report += "\n"
        }

        // All HID Devices Summary
        report += """
        
        ┌─────────────────────────────────────────────────────────┐
        │ ALL HID DEVICES (Summary)                               │
        └─────────────────────────────────────────────────────────┘
        
        Found \(results.allHIDDevices.count) total HID device interface(s)
        
        """
        
        // Critical Issues Summary
        if results.hasCriticalIssues {
            report += """
            
            ┌─────────────────────────────────────────────────────────┐
            │ ⚠️  CRITICAL ISSUES DETECTED                             │
            └─────────────────────────────────────────────────────────┘
            
            """
            if !results.ioHIDAccessGranted {
                report += "  • Missing IOKit HID Access (Input Monitoring permission)\n"
                report += "    Device enumeration may be incomplete until this is granted.\n"
            }
            if !results.accessibilityGranted {
                report += "  • Missing Accessibility permission\n"
            }
            if results.knownDevices.isEmpty && results.webexDevices.isEmpty {
                if !results.ioHIDAccessGranted {
                    report += "  • No recognized touch devices visible (may be hidden by missing permissions)\n"
                } else {
                    report += "  • No recognized touch device detected at USB level\n"
                }
            }
            if !results.webexDevices.isEmpty && results.touchInterfaces.isEmpty {
                report += "  • Desk Pro detected but touch digitizer interface not available\n"
                report += "    Try connecting HDMI + USB-C, or enable touch on the device.\n"
            }
            report += "\n"
        } else {
            report += """
            
            ┌─────────────────────────────────────────────────────────┐
            │ ✓ NO CRITICAL ISSUES - DEVICE READY                     │
            └─────────────────────────────────────────────────────────┘
            
            All permissions granted and touch interface available.
            If TouchRedirect still shows "Disconnected", check the app logs
            at /tmp/touchredirect.log for additional details.
            
            """
        }
        
        report += """
        ═══════════════════════════════════════════════════════════
        End of Diagnostic Report
        
        Save this report and include it when reporting issues.
        ═══════════════════════════════════════════════════════════
        
        """
        
        return report
    }
    
    /// Write diagnostic report to file and console
    static func runAndSaveDiagnostics() -> String {
        let report = generateReport()
        
        // Save to file
        let logPath = "/tmp/touchredirect-diagnostics.log"
        if let data = report.data(using: .utf8) {
            do {
                try data.write(to: URL(fileURLWithPath: logPath))
                print("Diagnostic report saved to: \(logPath)")
            } catch {
                print("Failed to save diagnostic report: \(error)")
            }
        }
        
        // Also print to console
        print(report)
        
        return logPath
    }
    
    // MARK: - Private Helpers
    
    private static func gatherSystemInfo() -> SystemInfo {
        var macModel = "Unknown"
        var chipModel = "Unknown"
        
        // Get Mac model
        if let modelData = runShellCommand("/usr/sbin/sysctl", ["-n", "hw.model"]) {
            macModel = modelData.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Get chip info
        if let cpuBrand = runShellCommand("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]) {
            chipModel = cpuBrand.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Get architecture
        let architecture: String
        #if arch(arm64)
        architecture = "arm64 (Apple Silicon)"
        #elseif arch(x86_64)
        architecture = "x86_64 (Intel)"
        #else
        architecture = "unknown"
        #endif
        
        // Get OS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        
        return SystemInfo(
            macModel: macModel,
            osVersion: osVersion,
            architecture: architecture,
            chipModel: chipModel
        )
    }
    
    private static func enumerateAllHIDDevices() -> [HIDDeviceInfo] {
        var devices: [HIDDeviceInfo] = []
        
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        // Match all HID devices (no filter)
        IOHIDManagerSetDeviceMatching(manager, nil)
        
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            return devices
        }
        
        if let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in deviceSet {
                if let info = extractDeviceInfo(device) {
                    devices.append(info)
                }
            }
        }
        
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        
        return devices
    }
    
    private static func extractDeviceInfo(_ device: IOHIDDevice) -> HIDDeviceInfo? {
        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        let manufacturer = IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String ?? "Unknown"
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        let interfaceID = IOHIDDeviceGetProperty(device, kIOHIDInterfaceIDKey as CFString) as? Int
        let locationID = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int
        
        return HIDDeviceInfo(
            vendorID: vendorID,
            productID: productID,
            product: product,
            manufacturer: manufacturer,
            usagePage: usagePage,
            usage: usage,
            interfaceID: interfaceID,
            locationID: locationID
        )
    }
    
    private static func checkIOHIDAccess() -> Bool {
        // Check if we can access HID devices
        // On macOS 10.15+, this requires Input Monitoring permission
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        let hasAccess = (openResult == kIOReturnSuccess)
        
        if hasAccess {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        
        return hasAccess
    }
    
    private static func findConflictingProcesses() -> [String] {
        var conflicts: [String] = []
        
        let processNames = ["WebexHelper", "UPPD", "CiscoTouchDriver", "webexHelper"]
        
        for processName in processNames {
            if isProcessRunning(processName) {
                conflicts.append(processName)
            }
        }
        
        return conflicts
    }
    
    private static func isProcessRunning(_ name: String) -> Bool {
        let output = runShellCommand("/bin/ps", ["-ax", "-o", "comm"])
        return output?.contains(name) ?? false
    }
    
    private static func checkEntitlements() -> [String: Bool] {
        var entitlements: [String: Bool] = [:]
        
        // Check permissions indirectly by attempting operations
        // (Direct entitlement reading requires Security framework)
        entitlements["com.apple.security.device.usb"] = checkIOHIDAccess()
        entitlements["accessibility"] = AXIsProcessTrusted()
        
        return entitlements
    }
    
    private static func runShellCommand(_ command: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    private static func formatStatus(_ label: String, _ status: Bool) -> String {
        let icon = status ? "✓" : "❌"
        let statusText = status ? "Granted" : "MISSING"
        let paddedLabel = (label + ":").padding(toLength: 40, withPad: " ", startingAt: 0)
        return "  \(icon) \(paddedLabel) \(statusText)\n"
    }
    
    private static func usagePageName(_ usagePage: Int) -> String {
        switch usagePage {
        case 0x01: return "Generic Desktop"
        case 0x0D: return "Digitizer"
        case 0x0C: return "Consumer"
        case 0x09: return "Button"
        default: return "Unknown"
        }
    }
    
    private static func usageName(_ usage: Int) -> String {
        switch usage {
        case 0x01: return "Pointer"
        case 0x02: return "Mouse"
        case 0x04: return "Touch Screen"
        case 0x06: return "Keyboard"
        default: return "Unknown"
        }
    }
}
