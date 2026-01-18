//
//  SettingsWindow.swift
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
//  SwiftUI-based settings interface with tabs for general, calibration,
//  gestures, and about information. Also includes onboarding flow.
//

import SwiftUI
import AppKit
import ApplicationServices
import IOKit.hid

// MARK: - Settings Window Host

/// Creates and manages the Settings window
class SettingsWindowController {
    private var window: NSWindow?
    
    func show() {
        if window == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            window = NSWindow(contentViewController: hostingController)
            window?.title = "TouchRedirect"
            window?.styleMask = [.titled, .closable, .miniaturizable]
            window?.setContentSize(NSSize(width: 480, height: 520))
            window?.center()
            window?.isReleasedWhenClosed = false
            window?.toolbarStyle = .preference  // Modern preference window style
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func close() {
        window?.close()
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape.fill")
                }
                .tag(0)
            
            CalibrationSettingsView()
                .tabItem {
                    Label("Calibration", systemImage: "scope")
                }
                .tag(1)
            
            GesturesSettingsView()
                .tabItem {
                    Label("Gestures", systemImage: "hand.draw.fill")
                }
                .tag(2)
            
            DiagnosticsSettingsView()
                .tabItem {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
                .tag(3)
            
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle.fill")
                }
                .tag(4)
        }
        .padding(20)
        .frame(minWidth: 450, minHeight: 420)
    }
}

// MARK: - General Tab

struct GeneralSettingsView: View {
    @State private var enabled = Config.shared.enabled
    @State private var launchAtLogin = Config.shared.launchAtLogin
    @State private var showActivityIndicator = Config.shared.showTouchActivityIndicator
    @State private var selectedScreenID: CGDirectDisplayID = CGDirectDisplayID(Config.shared.selectedDisplayID)
    @State private var availableScreens: [(id: CGDirectDisplayID, name: String, resolution: CGSize)] = []
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Touch Redirect", isOn: $enabled)
                    .onChange(of: enabled) { _, newValue in
                        Config.shared.enabled = newValue
                    }
                
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        Config.shared.launchAtLogin = newValue
                        LaunchAtLogin.shared.isEnabled = newValue
                    }
                
                Toggle("Show Touch Activity in Menu Bar", isOn: $showActivityIndicator)
                    .onChange(of: showActivityIndicator) { _, newValue in
                        Config.shared.showTouchActivityIndicator = newValue
                    }
            } header: {
                Text("General")
            }
            
            Section {
                Picker("Target Screen", selection: $selectedScreenID) {
                    Text("Auto-detect").tag(CGDirectDisplayID(0))
                    ForEach(availableScreens, id: \.id) { screen in
                        Text("\(screen.name) (\(Int(screen.resolution.width))×\(Int(screen.resolution.height)))")
                            .tag(screen.id)
                    }
                }
                .onChange(of: selectedScreenID) { _, newValue in
                    Config.shared.selectedDisplayID = Int(newValue)
                    ScreenManager.shared.selectScreen(displayID: newValue)
                }
                
                HStack {
                    Text("Current:")
                    Text("\(ScreenManager.shared.screenName)")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(ScreenManager.shared.screenFrame.width))×\(Int(ScreenManager.shared.screenFrame.height))")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Display")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshScreenList()
        }
    }
    
    private func refreshScreenList() {
        availableScreens = ScreenManager.shared.availableScreens
        selectedScreenID = CGDirectDisplayID(Config.shared.selectedDisplayID)
    }
}

// MARK: - Calibration Tab

struct CalibrationSettingsView: View {
    @State private var edgeBoostStrength = Config.shared.edgeBoostStrength
    @State private var hasCalibration = Config.shared.affineTransform != nil
    @State private var calibrationInfo: String = ""
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: hasCalibration ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(hasCalibration ? .green : .red)
                    Text(hasCalibration ? "Calibration: Active" : "Calibration: Not Set")
                }
                
                if hasCalibration {
                    Text(calibrationInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Button("Basic (5 points)") {
                        postCalibrationNotification(mode: "basic")
                    }
                    
                    Button("Advanced (9 points)") {
                        postCalibrationNotification(mode: "advanced")
                    }
                }
                
                Button("Reset to Defaults") {
                    Config.shared.resetAllCalibration()
                    hasCalibration = false
                    updateCalibrationInfo()
                }
                .foregroundColor(.red)
            } header: {
                Text("Calibration Status")
            }
            
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Edge Boost Strength")
                        Spacer()
                        Text("\(Int(edgeBoostStrength * 100))%")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $edgeBoostStrength, in: 0...0.3, step: 0.01)
                        .onChange(of: edgeBoostStrength) { _, newValue in
                            Config.shared.edgeBoostStrength = newValue
                        }
                    
                    Text("Compensates for the Desk Pro reserving edge zones for its own gestures. Higher values push touch closer to screen edges.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Edge Correction")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            updateCalibrationInfo()
        }
    }
    
    private func updateCalibrationInfo() {
        hasCalibration = Config.shared.affineTransform != nil
        
        if let res = Config.shared.calibrationResolution {
            let displayID = Config.shared.calibrationDisplayID
            calibrationInfo = "Calibrated for display \(displayID) at \(Int(res.width))×\(Int(res.height))"
        } else {
            calibrationInfo = ""
        }
    }
    
    private func postCalibrationNotification(mode: String) {
        NotificationCenter.default.post(
            name: Notification.Name("StartCalibration"),
            object: nil,
            userInfo: ["mode": mode]
        )
    }
}

// MARK: - Gestures Tab

struct GesturesSettingsView: View {
    @State private var scrollSensitivity = Config.shared.scrollSensitivity
    @State private var naturalScrolling = !Config.shared.reverseScrollDirection
    @State private var threeFingerSwipeEnabled = Config.shared.threeFingerSwipeEnabled
    @State private var pinchToZoomEnabled = Config.shared.pinchToZoomEnabled
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Scroll Sensitivity")
                        Spacer()
                        Text(String(format: "%.1fx", scrollSensitivity))
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $scrollSensitivity, in: 0.5...3.0, step: 0.1)
                        .onChange(of: scrollSensitivity) { _, newValue in
                            Config.shared.scrollSensitivity = newValue
                        }
                }
                
                Toggle("Natural Scrolling", isOn: $naturalScrolling)
                    .onChange(of: naturalScrolling) { _, newValue in
                        Config.shared.reverseScrollDirection = !newValue
                    }
            } header: {
                Text("Two-Finger Scroll")
            }
            
            Section {
                Toggle("Three-Finger Swipe Gestures", isOn: $threeFingerSwipeEnabled)
                    .onChange(of: threeFingerSwipeEnabled) { _, newValue in
                        Config.shared.threeFingerSwipeEnabled = newValue
                    }
                
                if threeFingerSwipeEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        GestureRow(gesture: "Swipe Up", action: "Mission Control")
                        GestureRow(gesture: "Swipe Down", action: "App Exposé")
                        
                        // Configurable desktop switching shortcuts
                        InlineShortcutPicker(
                            gesture: "Swipe Left",
                            keyCode: Binding(
                                get: { Config.shared.desktopLeftKeyCode },
                                set: { Config.shared.desktopLeftKeyCode = $0 }
                            ),
                            modifiers: Binding(
                                get: { Config.shared.desktopLeftModifiers },
                                set: { Config.shared.desktopLeftModifiers = $0 }
                            )
                        )
                        
                        InlineShortcutPicker(
                            gesture: "Swipe Right",
                            keyCode: Binding(
                                get: { Config.shared.desktopRightKeyCode },
                                set: { Config.shared.desktopRightKeyCode = $0 }
                            ),
                            modifiers: Binding(
                                get: { Config.shared.desktopRightModifiers },
                                set: { Config.shared.desktopRightModifiers = $0 }
                            )
                        )
                    }
                    .padding(.leading)
                }
            } header: {
                Text("Three-Finger Gestures")
            }
            
            Section {
                Toggle("Pinch to Zoom", isOn: $pinchToZoomEnabled)
                    .onChange(of: pinchToZoomEnabled) { _, newValue in
                        Config.shared.pinchToZoomEnabled = newValue
                    }
                
                if pinchToZoomEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        GestureRow(gesture: "Pinch In", action: "Zoom Out (⌘-)")
                        GestureRow(gesture: "Pinch Out", action: "Zoom In (⌘+)")
                    }
                    .padding(.leading)
                }
            } header: {
                Text("Pinch Gestures")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Inline Shortcut Picker (for gesture list)

struct InlineShortcutPicker: View {
    let gesture: String
    @Binding var keyCode: Int
    @Binding var modifiers: String
    
    // Common shortcut presets for desktop switching
    private let presets: [(name: String, keyCode: Int, modifiers: String)] = [
        ("⌃← Control+Left", 123, "control down"),
        ("⌃→ Control+Right", 124, "control down"),
        ("⌘← Command+Left", 123, "command down"),
        ("⌘→ Command+Right", 124, "command down"),
    ]
    
    private var selectedPresetIndex: Int {
        presets.firstIndex { $0.keyCode == keyCode && $0.modifiers == modifiers } ?? 0
    }
    
    var body: some View {
        HStack {
            Text(gesture)
                .foregroundColor(.secondary)
            Spacer()
            Picker("", selection: Binding(
                get: { selectedPresetIndex },
                set: { index in
                    keyCode = presets[index].keyCode
                    modifiers = presets[index].modifiers
                }
            )) {
                ForEach(0..<presets.count, id: \.self) { index in
                    Text(presets[index].name).tag(index)
                }
            }
            .labelsHidden()
            .frame(width: 160)
        }
        .font(.caption)
    }
}

struct GestureRow: View {
    let gesture: String
    let action: String
    
    var body: some View {
        HStack {
            Text(gesture)
                .foregroundColor(.secondary)
            Spacer()
            Text(action)
                .foregroundColor(.secondary)
        }
        .font(.caption)
    }
}

// MARK: - Diagnostics Tab

struct DiagnosticsSettingsView: View {
    @State private var diagnosticReport = ""
    @State private var isRunningDiagnostics = false
    @State private var systemInfo = getSystemInfo()
    @State private var hasAccessibility = AXIsProcessTrusted()
    @State private var hasInputMonitoring = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("System Diagnostics")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Troubleshoot device connection issues")
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // System Info
                GroupBox(label: Label("System Information", systemImage: "desktopcomputer")) {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Mac Model", value: systemInfo.model)
                        InfoRow(label: "Chip", value: systemInfo.chip)
                        InfoRow(label: "Architecture", value: systemInfo.architecture)
                        InfoRow(label: "macOS", value: systemInfo.osVersion)
                    }
                    .padding(8)
                }
                
                // Permission Status
                GroupBox(label: Label("Permissions", systemImage: "lock.shield")) {
                    VStack(alignment: .leading, spacing: 8) {
                        PermissionRow(
                            label: "Accessibility",
                            granted: hasAccessibility,
                            description: "Required to control cursor"
                        )
                        
                        PermissionRow(
                            label: "Input Monitoring",
                            granted: hasInputMonitoring,
                            description: "Required to access USB HID devices"
                        )
                        
                        if !hasAccessibility || !hasInputMonitoring {
                            Divider()
                                .padding(.vertical, 4)
                            
                            Button(action: openSystemSettings) {
                                Label("Open System Settings", systemImage: "gearshape")
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .padding(8)
                }
                
                // Quick Diagnostics
                GroupBox(label: Label("Quick Actions", systemImage: "wrench.and.screwdriver")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: checkPermissions) {
                            Label("Refresh Permission Status", systemImage: "arrow.clockwise")
                        }
                        
                        Button(action: openConsoleApp) {
                            Label("Open Console.app (View Logs)", systemImage: "terminal")
                        }
                        
                        Button(action: openSystemInformation) {
                            Label("Open System Information (USB)", systemImage: "info.circle")
                        }
                        
                        Button(action: openTroubleshootingGuide) {
                            Label("View Troubleshooting Guide", systemImage: "doc.text")
                        }
                    }
                    .padding(8)
                }
                
                // Full Diagnostics
                GroupBox(label: Label("Full Diagnostic Report", systemImage: "stethoscope")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Run comprehensive diagnostics to identify connection issues.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Button(action: runFullDiagnostics) {
                                if isRunningDiagnostics {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Running...")
                                } else {
                                    Label("Run Full Diagnostics", systemImage: "play.fill")
                                }
                            }
                            .disabled(isRunningDiagnostics)
                            
                            if !diagnosticReport.isEmpty {
                                Button(action: openDiagnosticLog) {
                                    Label("Open Log File", systemImage: "doc.text")
                                }
                                
                                Button(action: copyDiagnosticReport) {
                                    Label("Copy Report", systemImage: "doc.on.clipboard")
                                }
                            }
                        }
                        
                        if !diagnosticReport.isEmpty {
                            Divider()
                                .padding(.vertical, 4)
                            
                            ScrollView {
                                Text(diagnosticReport)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(height: 200)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                        }
                    }
                    .padding(8)
                }
            }
            .padding()
        }
        .onAppear {
            checkPermissions()
        }
    }
    
    private func checkPermissions() {
        hasAccessibility = AXIsProcessTrusted()
        hasInputMonitoring = checkInputMonitoringPermission()
    }
    
    private func checkInputMonitoringPermission() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let hidManager = manager else {
            return false
        }
        
        let openResult = IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        let hasAccess = (openResult == kIOReturnSuccess)
        
        if hasAccess {
            IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        
        return hasAccess
    }
    
    private func runFullDiagnostics() {
        isRunningDiagnostics = true
        diagnosticReport = ""
        
        DispatchQueue.global(qos: .userInitiated).async {
            let report = USBDiagnostics.generateReport()
            
            DispatchQueue.main.async {
                diagnosticReport = report
                isRunningDiagnostics = false
            }
        }
    }
    
    private func openDiagnosticLog() {
        let logPath = "/tmp/touchredirect-diagnostics.log"
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }
    
    private func copyDiagnosticReport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticReport, forType: .string)
    }
    
    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openConsoleApp() {
        NSWorkspace.shared.launchApplication("Console")
    }
    
    private func openSystemInformation() {
        NSWorkspace.shared.launchApplication("System Information")
    }
    
    private func openTroubleshootingGuide() {
        // Try to open TROUBLESHOOTING.md in workspace
        if let bundlePath = Bundle.main.resourcePath,
           let troubleshootingPath = Bundle.main.path(forResource: "TROUBLESHOOTING", ofType: "md") {
            NSWorkspace.shared.open(URL(fileURLWithPath: troubleshootingPath))
        } else {
            // Fallback to GitHub
            if let url = URL(string: "https://github.com/pwhizzard/touch-redirect-mac/blob/main/TROUBLESHOOTING.md") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private static func getSystemInfo() -> (model: String, chip: String, architecture: String, osVersion: String) {
        var model = "Unknown"
        var chip = "Unknown"
        
        if let modelData = runCommand("/usr/sbin/sysctl", ["-n", "hw.model"]) {
            model = modelData.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if let cpuBrand = runCommand("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]) {
            chip = cpuBrand.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let architecture: String
        #if arch(arm64)
        architecture = "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        architecture = "Intel (x86_64)"
        #else
        architecture = "Unknown"
        #endif
        
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        
        return (model, chip, architecture, osVersion)
    }
    
    private static func runCommand(_ command: String, _ arguments: [String]) -> String? {
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
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
            Spacer()
        }
        .font(.caption)
    }
}

struct PermissionRow: View {
    let label: String
    let granted: Bool
    let description: String
    
    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(granted ? "Granted" : "Missing")
                .font(.caption)
                .foregroundColor(granted ? .green : .red)
        }
    }
}

// MARK: - About Tab

struct AboutSettingsView: View {
    private let version = "1.0"
    private let buildDate = "January 2026"
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // App icon placeholder
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("TouchRedirect")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version \(version)")
                .foregroundColor(.secondary)
            
            Text("Control your Mac with touch input from Cisco WebEx Desk Pro")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Spacer()
            
            VStack(spacing: 8) {
                Text("Built with Swift and SwiftUI")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Licensed under GPL v3")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Onboarding Window

/// Creates and manages the first-run onboarding window
class OnboardingWindowController {
    private var window: NSWindow?
    var onComplete: (() -> Void)?
    
    func show() {
        if window == nil {
            let onboardingView = OnboardingView(onComplete: { [weak self] in
                self?.complete()
            })
            let hostingController = NSHostingController(rootView: onboardingView)
            
            window = NSWindow(contentViewController: hostingController)
            window?.title = "Welcome to TouchRedirect"
            window?.styleMask = [.titled, .closable]
            window?.setContentSize(NSSize(width: 500, height: 400))
            window?.center()
            window?.isReleasedWhenClosed = false
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func complete() {
        Config.shared.hasCompletedOnboarding = true
        window?.close()
        onComplete?()
    }
    
    func close() {
        window?.close()
    }
}

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var currentPage = 0
    @State private var hasAccessibilityPermission = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area
            TabView(selection: $currentPage) {
                WelcomePage()
                    .tag(0)
                
                PermissionsPage(hasPermission: $hasAccessibilityPermission)
                    .tag(1)
                
                CalibrationPage()
                    .tag(2)
            }
            .tabViewStyle(.automatic)
            
            Divider()
            
            // Navigation buttons
            HStack {
                if currentPage > 0 {
                    Button("Back") {
                        withAnimation { currentPage -= 1 }
                    }
                }
                
                Spacer()
                
                // Page dots
                HStack(spacing: 6) {
                    ForEach(0..<3) { page in
                        Circle()
                            .fill(page == currentPage ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Spacer()
                
                if currentPage < 2 {
                    Button("Continue") {
                        withAnimation { currentPage += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentPage == 1 && !hasAccessibilityPermission)
                } else {
                    Button("Get Started") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .onAppear {
            // Check if permission is already granted
            hasAccessibilityPermission = AXIsProcessTrusted()
        }
    }
}

struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("Welcome to TouchRedirect")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Turn your Cisco WebEx Desk Pro into a touch display for your Mac.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
}

struct PermissionsPage: View {
    @Binding var hasPermission: Bool
    @State private var isCheckingPermission = false
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            if hasPermission {
                // Permission granted state
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                
                Text("Permission Granted")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("TouchRedirect can now control your cursor. You're all set!")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 40)
            } else {
                // Permission needed state
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("Accessibility Permission Required")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("TouchRedirect needs Accessibility permission to control your cursor.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 40)
                
                Button(action: requestPermission) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                        Text("Open System Settings")
                    }
                    .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Text("Enable TouchRedirect in Privacy & Security → Accessibility")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .onAppear {
            checkPermission()
        }
    }
    
    private func requestPermission() {
        // This triggers the system permission dialog and opens System Settings
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // Start polling to check if permission was granted
        isCheckingPermission = true
        pollForPermission()
    }
    
    private func checkPermission() {
        hasPermission = AXIsProcessTrusted()
    }
    
    private func pollForPermission() {
        // Check every 0.5 seconds if permission was granted
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if AXIsProcessTrusted() {
                hasPermission = true
                isCheckingPermission = false
            } else if isCheckingPermission {
                pollForPermission()
            }
        }
    }
}

struct CalibrationPage: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "scope")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("Calibrate Your Touch Display")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("For accurate touch input, you'll need to calibrate by touching targets on screen.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 8) {
                Label("Connect your Desk Pro via USB-C", systemImage: "cable.connector")
                Label("Click the menu bar icon", systemImage: "menubar.arrow.up.rectangle")
                Label("Select Calibrate → Basic (5 points)", systemImage: "target")
            }
            .font(.callout)
            .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif
