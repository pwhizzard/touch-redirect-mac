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
            return usagePage == 0x0D && usage == 0x04
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
        let ioHIDAccessGranted: Bool
        let accessibilityGranted: Bool
        let conflictingProcesses: [String]
        let entitlementsPresent: [String: Bool]
        
        var hasCriticalIssues: Bool {
            return !ioHIDAccessGranted || !accessibilityGranted || webexDevices.isEmpty
        }
    }
    
    // MARK: - Public API
    
    /// Run full diagnostics and return structured results
    static func runDiagnostics() -> DiagnosticResults {
        let systemInfo = gatherSystemInfo()
        let allDevices = enumerateAllHIDDevices()
        let webexDevices = allDevices.filter { $0.isWebExDeskPro }
        let touchInterfaces = webexDevices.filter { $0.isTouchInterface }
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
        
        // WebEx Desk Pro Detection
        report += """
        
        
        ┌─────────────────────────────────────────────────────────┐
        │ CISCO WEBEX DESK PRO DETECTION                          │
        └─────────────────────────────────────────────────────────┘
        
        """
        if results.webexDevices.isEmpty {
            report += """
              ❌ NO WEBEX DESK PRO DETECTED
              
              The device is not visible to macOS at the USB level.
              
              Troubleshooting steps:
              1. Verify USB-C cable is data-capable (not charge-only)
              2. Try different USB-C ports on your Mac
              3. Try connecting BOTH HDMI + USB-C cables
              4. Power cycle the Desk Pro (unplug power, wait 30s)
              5. Check System Information → USB for any Cisco devices
              6. Kill conflicting software (UPPD, WebexHelper)
              
              If you previously used UPPD software, it may have changed
              the device configuration to require HDMI + USB-C.
              
            """
        } else {
            report += "  ✓ Found \(results.webexDevices.count) Cisco WebEx Desk Pro interface(s)\n\n"
            for (index, device) in results.webexDevices.enumerated() {
                report += """
                  Interface #\(index + 1):
                    Product:      \(device.product)
                    Manufacturer: \(device.manufacturer)
                    Vendor ID:    0x\(String(device.vendorID, radix: 16))
                    Product ID:   0x\(String(device.productID, radix: 16))
                    Usage Page:   0x\(String(device.usagePage, radix: 16)) (\(usagePageName(device.usagePage)))
                    Usage:        0x\(String(device.usage, radix: 16)) (\(usageName(device.usage)))
                
                """
                if device.isTouchInterface {
                    report += "    ✓ This is the TOUCH SCREEN interface\n\n"
                } else {
                    report += "    ℹ️  Not the touch interface (different usage page/usage)\n\n"
                }
            }
        }
        
        // Touch Interface Status
        report += """
        
        ┌─────────────────────────────────────────────────────────┐
        │ TOUCH INTERFACE STATUS                                  │
        └─────────────────────────────────────────────────────────┘
        
        """
        if results.touchInterfaces.isEmpty {
            if results.webexDevices.isEmpty {
                report += "  ❌ Device not detected (see above)\n"
            } else {
                report += """
                  ⚠️  DEVICE FOUND BUT TOUCH INTERFACE MISSING
                  
                  The Desk Pro is detected, but the touch digitizer interface
                  (Usage Page 0x0D, Usage 0x04) is not available.
                  
                  Possible causes:
                  1. Touch interface is disabled on the device
                  2. Device requires HDMI connection to enable touch
                  3. Conflicting software has exclusive access
                  4. Device firmware issue
                  
                  Try:
                  • Connect HDMI cable in addition to USB-C
                  • Look for "Enable Touch" button on the Desk Pro screen
                  • Kill WebexHelper/UPPD: killall WebexHelper
                  • Update Desk Pro firmware if available
                  
                """
            }
        } else {
            report += "  ✓ Touch interface detected and available!\n\n"
            if !results.ioHIDAccessGranted {
                report += """
                  ⚠️  However, IOKit HID permission is missing.
                     Grant Input Monitoring permission in System Settings.
                  
                """
            }
            if !results.accessibilityGranted {
                report += """
                  ⚠️  Accessibility permission is missing.
                     Required to inject cursor events.
                  
                """
            }
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
            }
            if !results.accessibilityGranted {
                report += "  • Missing Accessibility permission\n"
            }
            if results.webexDevices.isEmpty {
                report += "  • WebEx Desk Pro not detected at USB level\n"
            }
            if !results.touchInterfaces.isEmpty && results.touchInterfaces.isEmpty {
                report += "  • Device detected but touch interface not available\n"
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
        guard manager != nil else {
            return devices
        }
        
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
        guard manager != nil else {
            return false
        }
        
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
        return String(format: "  %@ %-40s %@\n", icon, label + ":", statusText)
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
