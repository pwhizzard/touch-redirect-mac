//
//  AppDelegate.swift
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
//  Main application delegate - manages menu bar, HID device connection,
//  calibration flow, and coordinates touch processing components.
//

import Cocoa
import IOKit.hid

// MARK: - Logging

/// Debug logging - only active in DEBUG builds
/// Use for verbose diagnostic information
func log(_ message: String) {
    #if DEBUG
    let logPath = "/tmp/touchredirect.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    
    if let data = line.data(using: .utf8) {
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: data)
        }
    }
    print(message)
    #endif
}

/// Error logging - always active, for critical issues
func logError(_ message: String) {
    let logPath = "/tmp/touchredirect.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] ERROR: \(message)\n"
    
    if let data = line.data(using: .utf8) {
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: data)
        }
    }
    print("ERROR: \(message)")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var statusMenuItem: NSMenuItem!
    var screenMenuItem: NSMenuItem!
    var enabledMenuItem: NSMenuItem!
    var hidManager: HIDManager!
    
    // Touch processing components
    let mapper = Mapper()
    let injector = Injector()
    var gestureEngine: GestureEngine!
    
    // Calibration
    var calibrationWindow: CalibrationWindow?
    var isCalibrating: Bool = false
    /// The device identity being used for calibration (nil = accept any / legacy single-device)
    var calibrationDeviceIdentity: TouchDeviceIdentity?
    var isShowingRecalibrationPrompt: Bool = false
    var lastRecalibrationPromptTime: Date = .distantPast
    var lastRecalibrationPromptDisplayID: CGDirectDisplayID = 0
    var lastRecalibrationPromptResolution: CGSize = .zero
    
    // Settings window
    var settingsController: SettingsWindowController?
    
    // Onboarding
    var onboardingController: OnboardingWindowController?
    
    // Accessibility permission state
    var hasAccessibilityPermission: Bool = false
    var accessibilityCheckTimer: Timer?
    
    // Input Monitoring permission state
    var hasInputMonitoringPermission: Bool = false
    var inputMonitoringCheckTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Clear old log first
        try? FileManager.default.removeItem(atPath: "/tmp/touchredirect.log")
        
        log("TouchRedirect starting...")
        log(String(repeating: "=", count: 50))

        // Remove stale arbitration settings from earlier versions
        Config.shared.cleanupLegacyArbitrationKeys()
        
        // Initialize and log screen manager state
        ScreenManager.shared.updateTargetScreen()
        log("Screen: \(ScreenManager.shared.screenName)")
        log("  Frame: \(Int(ScreenManager.shared.screenFrame.width))x\(Int(ScreenManager.shared.screenFrame.height))")
        log("  Origin: (\(Int(ScreenManager.shared.screenFrame.origin.x)), \(Int(ScreenManager.shared.screenFrame.origin.y)))")
        
        // Initialize gesture engine
        gestureEngine = GestureEngine(mapper: mapper, injector: injector)
        
        // Apply config to mapper
        mapper.invertY = Config.shared.invertY
        
        // Load saved calibration (affine transform or fallback to linear)
        loadCalibration()
        
        // Log mapper state
        log("Mapper screen: \(Int(ScreenManager.shared.screenFrame.width))x\(Int(ScreenManager.shared.screenFrame.height))")
        
        // Check if calibration is valid for current screen/resolution
        checkCalibrationValidity()
        
        // Set up callback for calibration invalidation
        mapper.onCalibrationInvalidated = { [weak self] in
            self?.handleCalibrationInvalidated()
        }
        
        // Always ensure enabled on startup
        if !Config.shared.enabled {
            log("Config.enabled was false, resetting to true")
            Config.shared.enabled = true
        }
        log("Config.enabled = \(Config.shared.enabled)")
        
        // Check permission state before menu setup (without prompting)
        hasAccessibilityPermission = AXIsProcessTrusted()
        hasInputMonitoringPermission = checkInputMonitoringPermission()
        
        setupMenuBar()
        setupHIDManager()
        
        // Check launch at login status
        LaunchAtLogin.shared.checkStatus()
        
        // Show onboarding on first launch, otherwise check permissions
        if !Config.shared.hasCompletedOnboarding {
            showOnboarding()
        } else {
            // Only check permissions after onboarding is complete
            checkAccessibilityPermissions()
            checkInputMonitoringPermissions()
        }
        
        // Listen for calibration requests from Settings UI
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCalibrationRequest(_:)),
            name: Notification.Name("StartCalibration"),
            object: nil
        )
        
        // Listen for enabled state changes (from Settings UI)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEnabledChanged),
            name: .touchRedirectEnabledChanged,
            object: nil
        )

        // Listen for reset calibration requests (from Settings UI)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(resetCalibration),
            name: Notification.Name("ResetCalibration"),
            object: nil
        )
        
        log(String(repeating: "=", count: 50))
        log("TouchRedirect started - menu bar icon should be visible")
    }
    
    @objc private func handleEnabledChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let isConnected = self.hidManager?.isDeviceConnected ?? false
            self.updateMenuBarIcon(enabled: Config.shared.enabled, connected: isConnected)
            self.enabledMenuItem?.state = Config.shared.enabled ? .on : .off
        }
    }
    
    @objc private func handleCalibrationRequest(_ notification: Notification) {
        guard let mode = notification.userInfo?["mode"] as? String else { return }
        
        if mode == "basic" {
            startCalibration(mode: .basic)
        } else if mode == "advanced" {
            startCalibration(mode: .advanced)
        }
    }
    
    private func loadCalibration() {
        // Try to load affine transform
        if let transformData = Config.shared.affineTransform {
            mapper.loadTransformValues(transformData)
            log("Loaded affine calibration from config")
        } else {
            // Fallback to legacy linear calibration
            log("No affine calibration found, using linear fallback")
            mapper.setTouchRange(
                minX: CGFloat(Config.shared.calibrationMinX),
                maxX: CGFloat(Config.shared.calibrationMaxX),
                minY: CGFloat(Config.shared.calibrationMinY),
                maxY: CGFloat(Config.shared.calibrationMaxY)
            )
        }
    }
    
    private func checkAccessibilityPermissions(prompt: Bool = true) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        let wasGranted = hasAccessibilityPermission
        hasAccessibilityPermission = trusted
        
        if !trusted {
            logError("⚠️  Accessibility permission required for cursor control")
            logError("   Go to: System Settings → Privacy & Security → Accessibility")
            logError("   Add and enable TouchRedirect")
            
            // Start periodic check if not already running
            if accessibilityCheckTimer == nil {
                accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                    self?.checkAccessibilityPermissions(prompt: false)
                }
            }
        } else {
            log("✓ Accessibility permission granted")
            
            // Stop periodic check once granted
            accessibilityCheckTimer?.invalidate()
            accessibilityCheckTimer = nil
            
            // Update UI to reflect granted state
            if !wasGranted {
                updateStatusBarMenu()
            }
        }
    }
    
    private func checkInputMonitoringPermission() -> Bool {
        // Check IOHIDManager access (requires Input Monitoring on macOS 10.15+)
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        let hasAccess = (openResult == kIOReturnSuccess)
        
        if hasAccess {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        
        return hasAccess
    }
    
    private func checkInputMonitoringPermissions(prompt: Bool = true) {
        let hasAccess = checkInputMonitoringPermission()
        
        let wasGranted = hasInputMonitoringPermission
        hasInputMonitoringPermission = hasAccess
        
        if !hasAccess {
            logError("⚠️  Input Monitoring permission required for HID device access")
            logError("   Go to: System Settings → Privacy & Security → Input Monitoring")
            logError("   Add and enable TouchRedirect")
            logError("   You may need to restart the app after granting permission")
            
            // Show alert if not already shown
            if prompt && !wasGranted {
                DispatchQueue.main.async { [weak self] in
                    self?.showInputMonitoringAlert()
                }
            }
            
            // Start periodic check if not already running
            if inputMonitoringCheckTimer == nil {
                inputMonitoringCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                    self?.checkInputMonitoringPermissions(prompt: false)
                }
            }
        } else {
            log("✓ Input Monitoring permission granted")
            
            // Stop periodic check once granted
            inputMonitoringCheckTimer?.invalidate()
            inputMonitoringCheckTimer = nil
            
            // Update UI to reflect granted state
            if !wasGranted {
                updateStatusBarMenu()
            }
        }
    }
    
    private func showInputMonitoringAlert() {
        let alert = NSAlert()
        alert.messageText = "Input Monitoring Permission Required"
        alert.informativeText = """
        TouchRedirect needs Input Monitoring permission to access USB HID touch devices.
        
        Please grant permission in:
        System Settings → Privacy & Security → Input Monitoring
        
        You may need to restart TouchRedirect after granting permission.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open System Settings to Privacy & Security
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func setupHIDManager() {
        hidManager = HIDManager(appDelegate: self)

        // Set up touch report callback for gesture processing
        hidManager.onTouchReport = { [weak self] report in
            self?.gestureEngine.processTouchReport(report)

            // Show touch activity indicator if enabled
            if Config.shared.showTouchActivityIndicator && !report.touches.isEmpty {
                self?.flashTouchActivity()
            }
        }

        // Clean up stale per-device mappers and active device state on device changes
        hidManager.onDeviceRegistryChanged = { [weak self] in
            guard let self = self else { return }
            let connectedIdentities = Set(self.hidManager.connectedDevices.keys)
            self.gestureEngine.cleanupDisconnectedDevices(connectedIdentities: connectedIdentities)
        }
    }
    
    // Touch activity indicator
    private var activityFlashTimer: Timer?
    private var isShowingActivity = false
    
    private func flashTouchActivity() {
        // Debounce - don't flash too rapidly
        guard !isShowingActivity else { return }
        isShowingActivity = true
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem.button else { return }
            
            // Flash the icon to a highlighted state
            let highlightSymbol = NSImage(
                systemSymbolName: "hand.point.up.left.and.text",
                accessibilityDescription: "Touch Active"
            )
            highlightSymbol?.isTemplate = true
            button.image = highlightSymbol
            
            // Restore after a short delay
            self.activityFlashTimer?.invalidate()
            self.activityFlashTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.isShowingActivity = false
                let isConnected = self.hidManager?.isDeviceConnected ?? false
                self.updateMenuBarIcon(enabled: Config.shared.enabled, connected: isConnected)
            }
        }
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if statusItem.button != nil {
            updateMenuBarIcon(enabled: Config.shared.enabled, connected: false)
        }
        
        let menu = NSMenu()
        
        // Status item
        statusMenuItem = NSMenuItem(title: "Status: Disconnected", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        // Screen selection submenu
        let screenMenu = NSMenu()
        rebuildScreenMenu(screenMenu)
        
        let sm = ScreenManager.shared
        let screenInfo = "\(sm.screenName) (\(Int(sm.screenFrame.width))×\(Int(sm.screenFrame.height)))"
        screenMenuItem = NSMenuItem(title: "Screen: \(screenInfo)", action: nil, keyEquivalent: "")
        screenMenuItem.submenu = screenMenu
        menu.addItem(screenMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Enabled toggle
        enabledMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "e")
        enabledMenuItem.target = self
        enabledMenuItem.state = Config.shared.enabled ? .on : .off
        menu.addItem(enabledMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Calibration submenu
        let calibrationMenu = NSMenu()
        
        let basicCalibItem = NSMenuItem(title: "Basic (5 points)", action: #selector(startBasicCalibration), keyEquivalent: "")
        basicCalibItem.target = self
        calibrationMenu.addItem(basicCalibItem)
        
        let advancedCalibItem = NSMenuItem(title: "Advanced (9 points)", action: #selector(startAdvancedCalibration), keyEquivalent: "")
        advancedCalibItem.target = self
        calibrationMenu.addItem(advancedCalibItem)
        
        calibrationMenu.addItem(NSMenuItem.separator())
        
        let resetCalibItem = NSMenuItem(title: "Reset to Default", action: #selector(resetCalibration), keyEquivalent: "")
        resetCalibItem.target = self
        calibrationMenu.addItem(resetCalibItem)
        
        let calibMenuItem = NSMenuItem(title: "Calibrate...", action: nil, keyEquivalent: "")
        calibMenuItem.submenu = calibrationMenu
        menu.addItem(calibMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings item
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit item
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        Config.shared.enabled.toggle()
        sender.state = Config.shared.enabled ? .on : .off
        log("Touch redirect \(Config.shared.enabled ? "enabled" : "disabled")")
        
        // Update menu bar icon to reflect enabled state
        let isConnected = hidManager?.isDeviceConnected ?? false
        updateMenuBarIcon(enabled: Config.shared.enabled, connected: isConnected)
    }
    
    
    @objc private func startBasicCalibration() {
        startCalibration(mode: .basic)
    }
    
    @objc private func startAdvancedCalibration() {
        startCalibration(mode: .advanced)
    }
    
    /// Current calibration mode (for restart after screen switch)
    private var currentCalibrationMode: CalibrationMode = .basic
    
    private func startCalibration(mode: CalibrationMode) {
        guard !isCalibrating else {
            log("Calibration already in progress")
            return
        }
        
        log(String(repeating: "=", count: 50))
        log("Starting \(mode == .basic ? "basic (5-point)" : "advanced (9-point)") calibration...")
        isCalibrating = true
        currentCalibrationMode = mode
        
        calibrationWindow = CalibrationWindow(
            mode: mode,
            onComplete: { [weak self] points in
                self?.completeCalibration(points: points)
            },
            onCancel: { [weak self] in
                self?.cancelCalibration()
            }
        )
        
        // Handle screen switch request (Tab key)
        calibrationWindow?.onSwitchScreen = { [weak self] in
            self?.switchCalibrationScreen()
        }
        
        // Route touch data to calibration window, locked to a single source device
        calibrationDeviceIdentity = nil  // Will be set on first touch
        hidManager.onTouchReport = { [weak self] report in
            guard let self = self else { return }

            // Lock calibration to the first device that provides a touch
            if let sourceIdentity = report.deviceIdentity {
                if self.calibrationDeviceIdentity == nil {
                    // First touch during calibration — lock to this device
                    if report.touches.contains(where: { $0.tipSwitch }) {
                        self.calibrationDeviceIdentity = sourceIdentity
                        let entry = self.hidManager.connectedDevices[sourceIdentity]
                        log("Calibration locked to device: \(entry?.profile.displayName ?? "Unknown") (\(sourceIdentity))")
                    }
                } else if sourceIdentity != self.calibrationDeviceIdentity {
                    // Different device — ignore during calibration
                    return
                }
            }

            if let touch = report.touches.first {
                self.calibrationWindow?.handleTouch(
                    rawX: CGFloat(touch.x),
                    rawY: CGFloat(touch.y),
                    isTouching: touch.tipSwitch
                )
            } else {
                self.calibrationWindow?.handleTouch(rawX: 0, rawY: 0, isTouching: false)
            }
        }
        
        calibrationWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Switch calibration to the next available screen
    private func switchCalibrationScreen() {
        let screens = ScreenManager.shared.availableScreens
        guard screens.count > 1 else {
            log("Only one screen available, cannot switch")
            return
        }
        
        // Find current screen index
        let currentID = ScreenManager.shared.displayID
        var currentIndex = screens.firstIndex(where: { $0.id == currentID }) ?? 0
        
        // Cycle to next screen
        currentIndex = (currentIndex + 1) % screens.count
        let nextScreen = screens[currentIndex]
        
        log("Switching calibration to screen: \(nextScreen.name)")
        
        // Update the selected display
        ScreenManager.shared.selectedDisplayID = nextScreen.id
        Config.shared.selectedDisplayID = Int(nextScreen.id)
        
        // Close current calibration window
        calibrationWindow?.orderOut(nil)
        calibrationWindow = nil
        isCalibrating = false
        
        // Restart calibration on new screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.startCalibration(mode: self.currentCalibrationMode)
        }
        
        // Update menu to reflect new screen selection
        setupMenuBar()
    }
    
    private func completeCalibration(points: [CalibrationPoint]) {
        log("Calibration completed with \(points.count) points")
        
        // Convert calibration points to format needed for affine transform
        var calibrationPairs: [(touch: CGPoint, screen: CGPoint)] = []
        
        for point in points {
            if let pair = point.asTuple {
                calibrationPairs.append(pair)
                log("  Point: touch(\(Int(pair.touch.x)), \(Int(pair.touch.y))) -> screen(\(Int(pair.screen.x)), \(Int(pair.screen.y)))")
            }
        }
        
        guard calibrationPairs.count >= 3 else {
            logError("Need at least 3 valid calibration points")
            finishCalibration()
            return
        }
        
        // Compute affine transform using least-squares fitting
        log("Computing affine transform from \(calibrationPairs.count) points...")
        
        guard let transform = AffineTransform2D.fromCalibrationPoints(calibrationPairs) else {
            logError("Failed to compute affine transform")
            finishCalibration()
            return
        }
        
        // Validate the transform by checking corner accuracy
        log("Validating transform accuracy...")
        var maxError: CGFloat = 0
        for pair in calibrationPairs {
            let mapped = transform.apply(x: pair.touch.x, y: pair.touch.y)
            let error = sqrt(pow(mapped.x - pair.screen.x, 2) + pow(mapped.y - pair.screen.y, 2))
            maxError = max(maxError, error)
        }
        log("  Max calibration error: \(String(format: "%.2f", maxError)) pixels")
        
        if maxError > 50 {
            logError("Calibration error is high. Consider recalibrating.")
        }
        
        // Apply transform to global mapper (legacy / fallback path)
        mapper.setAffineTransform(transform)

        // Save transform to global config (always, for backward compat)
        let transformValues = mapper.getTransformValues()
        Config.shared.affineTransform = transformValues

        // Save the display ID and resolution used for calibration (global)
        let sm = ScreenManager.shared
        Config.shared.calibrationDisplayID = Int(sm.displayID)
        Config.shared.calibrationResolution = (
            width: Double(sm.screenFrame.width),
            height: Double(sm.screenFrame.height)
        )

        // Also save per-device calibration if we know which device was calibrating
        if let deviceIdentity = calibrationDeviceIdentity {
            let deviceKey = deviceIdentity.persistenceKey
            Config.shared.setAffineTransform(transformValues, forDevice: deviceKey)
            Config.shared.setCalibrationDisplayID(Int(sm.displayID), forDevice: deviceKey)
            Config.shared.setCalibrationResolution(
                (width: Double(sm.screenFrame.width), height: Double(sm.screenFrame.height)),
                forDevice: deviceKey
            )

            // Also look up the per-device mapper in GestureEngine and update it
            if let entry = hidManager.connectedDevices[deviceIdentity] {
                let deviceMapper = gestureEngine.mapper(for: deviceIdentity, profile: entry.profile)
                deviceMapper.setAffineTransform(transform)
                log("Per-device calibration saved for \(entry.profile.displayName) (\(deviceIdentity))")
            }
        }

        log("Calibration saved for display \(sm.displayID) at \(Int(sm.screenFrame.width))x\(Int(sm.screenFrame.height))")
        log(String(repeating: "=", count: 50))

        // Notify observers (e.g. Settings UI) that calibration changed
        NotificationCenter.default.post(name: .calibrationDidChange, object: nil)

        finishCalibration()
    }
    
    private func cancelCalibration() {
        log("Calibration cancelled")
        finishCalibration()
    }
    
    private func finishCalibration() {
        guard isCalibrating else {
            log("finishCalibration called but not calibrating, ignoring")
            return
        }

        log("Finishing calibration...")
        isCalibrating = false
        calibrationDeviceIdentity = nil

        let window = calibrationWindow
        calibrationWindow = nil
        
        // Restore normal touch processing (including touch activity indicator)
        hidManager.onTouchReport = { [weak self] report in
            self?.gestureEngine.processTouchReport(report)

            // Show touch activity indicator if enabled
            if Config.shared.showTouchActivityIndicator && !report.touches.isEmpty {
                self?.flashTouchActivity()
            }
        }
        
        DispatchQueue.main.async {
            window?.orderOut(nil)
            log("Calibration cleanup complete")
        }
    }
    
    @objc private func resetCalibration() {
        log("Resetting all calibration to defaults (global + per-device)")

        // Reset the global/legacy mapper
        mapper.resetCalibration()

        // Clear all persisted calibration data (global + device.* keys)
        Config.shared.resetAllCalibration()

        // Also reset legacy linear keys to their defaults
        Config.shared.calibrationMinX = 88
        Config.shared.calibrationMaxX = 15859
        Config.shared.calibrationMinY = 86
        Config.shared.calibrationMaxY = 9525

        // Flush per-device mapper cache so they reload fresh defaults
        gestureEngine.resetAllMappers()

        // Notify observers (e.g. Settings UI) that calibration changed
        NotificationCenter.default.post(name: .calibrationDidChange, object: nil)
    }
    
    // MARK: - Screen Selection
    
    private func rebuildScreenMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        
        let sm = ScreenManager.shared
        let screens = sm.availableScreens
        let selectedID = sm.selectedDisplayID
        
        // Auto-detect option
        let autoItem = NSMenuItem(title: "Auto-detect", action: #selector(selectAutoScreen), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = selectedID == 0 ? .on : .off
        menu.addItem(autoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Individual screens
        for screen in screens {
            let title = "\(screen.name) (\(Int(screen.resolution.width))×\(Int(screen.resolution.height)))"
            let item = NSMenuItem(title: title, action: #selector(selectScreen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = screen.id
            item.state = screen.id == selectedID ? .on : (selectedID == 0 && screen.id == sm.displayID ? .mixed : .off)
            menu.addItem(item)
        }
    }
    
    @objc private func selectAutoScreen() {
        log("Switching to auto-detect screen selection")
        ScreenManager.shared.selectScreen(displayID: 0)
        updateScreenMenuItem()
        rebuildScreenMenu(screenMenuItem.submenu!)
    }
    
    @objc private func selectScreen(_ sender: NSMenuItem) {
        guard let displayID = sender.representedObject as? CGDirectDisplayID else { return }
        log("User selected screen: \(displayID)")
        ScreenManager.shared.selectScreen(displayID: displayID)
        updateScreenMenuItem()
        rebuildScreenMenu(screenMenuItem.submenu!)
        
        // Warn about recalibration
        if mapper.hasAffineCalibration {
            log("Screen changed - may need recalibration")
        }
    }
    
    // MARK: - Settings Window
    
    @objc private func openSettings() {
        log("Opening settings window")
        
        if settingsController == nil {
            settingsController = SettingsWindowController()
        }
        
        settingsController?.show()
    }
    
    // MARK: - Onboarding
    
    private func showOnboarding() {
        log("Showing first-run onboarding")
        
        onboardingController = OnboardingWindowController()
        onboardingController?.onComplete = { [weak self] in
            log("Onboarding completed")
            // Offer to start calibration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.startCalibration(mode: .basic)
            }
        }
        onboardingController?.show()
    }
    
    func updateStatus(connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            var status = connected ? "Status: Connected" : "Status: Disconnected"
            if !self.hasAccessibilityPermission {
                status += " ⚠️ Accessibility Required"
                // Make it clickable when permission is needed
                self.statusMenuItem.action = #selector(self.openAccessibilitySettings)
                self.statusMenuItem.target = self
                self.statusMenuItem.isEnabled = true
            } else {
                // Disable when permission is granted (just info display)
                self.statusMenuItem.action = nil
                self.statusMenuItem.target = nil
                self.statusMenuItem.isEnabled = false
            }
            self.statusMenuItem.title = status
            self.updateMenuBarIcon(enabled: Config.shared.enabled, connected: connected)
        }
    }
    
    /// Open System Settings to the Accessibility pane
    @objc private func openAccessibilitySettings() {
        // Try to open System Settings directly to Accessibility > Privacy
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        
        // Also re-prompt for permission (will highlight the app in the list)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Update the status bar menu (called when permission state changes)
    private func updateStatusBarMenu() {
        let connected = hidManager?.isDeviceConnected ?? false
        updateStatus(connected: connected)
    }
    
    /// Update the menu bar icon based on enabled and connected state
    private func updateMenuBarIcon(enabled: Bool, connected: Bool) {
        guard let button = statusItem.button else { return }
        
        // Use SF Symbols for a clean, Apple-style icon
        // hand.point.up.left.fill - finger pointing (touch gesture)
        let symbolName: String
        let symbolConfig: NSImage.SymbolConfiguration
        
        if enabled {
            // Enabled state: solid finger icon
            symbolName = "hand.point.up.left.fill"
            symbolConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        } else {
            // Disabled state: slashed/crossed out finger
            symbolName = "hand.point.up.left"
            symbolConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .light)
        }
        
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "TouchRedirect") {
            let configuredImage = image.withSymbolConfiguration(symbolConfig)
            configuredImage?.isTemplate = true  // Adapts to menu bar appearance
            button.image = configuredImage
            button.imagePosition = .imageOnly
            button.title = ""  // Clean icon-only appearance
        } else {
            // Fallback to text if SF Symbol not available
            button.image = nil
            button.title = enabled ? "TR" : "tr"
        }
    }
    
    /// Update the screen info shown in menu
    private func updateScreenMenuItem() {
        let sm = ScreenManager.shared
        let screenInfo = "\(sm.screenName) (\(Int(sm.screenFrame.width))×\(Int(sm.screenFrame.height)))"
        screenMenuItem?.title = "Screen: \(screenInfo)"
    }
    
    /// Check if saved calibration matches current screen/resolution
    private func checkCalibrationValidity() {
        let sm = ScreenManager.shared
        let currentDisplayID = Int(sm.displayID)
        let currentWidth = Double(sm.screenFrame.width)
        let currentHeight = Double(sm.screenFrame.height)
        
        let savedDisplayID = Config.shared.calibrationDisplayID
        let savedResolution = Config.shared.calibrationResolution
        
        // No saved calibration data = skip check
        guard Config.shared.affineTransform != nil else {
            log("No calibration saved, skipping validity check")
            return
        }
        
        var isValid = true
        
        // Check if display changed
        if savedDisplayID != 0 && savedDisplayID != currentDisplayID {
            logError("Calibration was done on display \(savedDisplayID), current is \(currentDisplayID)")
            isValid = false
        }
        
        // Check if resolution changed significantly (>5%)
        if let savedRes = savedResolution {
            let widthChange = abs(currentWidth - savedRes.width) / savedRes.width
            let heightChange = abs(currentHeight - savedRes.height) / savedRes.height
            
            if widthChange > 0.05 || heightChange > 0.05 {
                logError("Resolution changed from \(Int(savedRes.width))x\(Int(savedRes.height)) to \(Int(currentWidth))x\(Int(currentHeight))")
                isValid = false
            }
        }
        
        if !isValid {
            log("Calibration may be invalid for current screen configuration")
            // Could show an alert here, but for now just log
        }
    }
    
    /// Whether the current screen configuration warrants recalibration
    private func shouldPromptForRecalibration() -> Bool {
        // Only prompt if we have an affine calibration saved
        guard Config.shared.affineTransform != nil else { return false }

        let sm = ScreenManager.shared
        let currentDisplayID = Int(sm.displayID)
        let currentWidth = Double(sm.screenFrame.width)
        let currentHeight = Double(sm.screenFrame.height)

        let savedDisplayID = Config.shared.calibrationDisplayID
        let savedResolution = Config.shared.calibrationResolution

        // If calibration was tied to a specific display and it differs, prompt
        if savedDisplayID != 0 && savedDisplayID != currentDisplayID {
            return true
        }

        // If resolution changed significantly, prompt
        if let savedRes = savedResolution {
            let widthChange = abs(currentWidth - savedRes.width) / savedRes.width
            let heightChange = abs(currentHeight - savedRes.height) / savedRes.height
            if widthChange > 0.05 || heightChange > 0.05 {
                return true
            }
        }

        return false
    }

    /// Pending work item for debounced recalibration check
    private var pendingRecalibrationCheck: DispatchWorkItem?
    
    /// Handle calibration being invalidated due to screen change
    private func handleCalibrationInvalidated() {
        log("Screen change detected, debouncing...")
        
        // Cancel any pending check - we want to wait for stability
        pendingRecalibrationCheck?.cancel()
        
        // Create a new delayed check
        let workItem = DispatchWorkItem { [weak self] in
            self?.performRecalibrationCheck()
        }
        pendingRecalibrationCheck = workItem
        
        // Wait 4 seconds for screen configuration to stabilize
        // If another change happens, this timer will be cancelled and restarted
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: workItem)
    }
    
    /// Actually check if recalibration is needed (called after debounce)
    private func performRecalibrationCheck() {
        log("Debounce complete, checking if recalibration prompt is needed...")
        
        // Re-check conditions after the delay
        guard hidManager?.isDeviceConnected == true else {
            log("Touch device not connected, skipping recalibration prompt")
            return
        }
        
        guard shouldPromptForRecalibration() else {
            log("Calibration still valid for current screen, skipping prompt")
            return
        }
        
        log("Screen configuration changed and calibration may be invalid")
        
        updateScreenMenuItem()
        
        // Don't show if already calibrating
        if isCalibrating {
            log("Already calibrating, skipping recalibration prompt")
            return
        }
        
        // Don't show if already showing prompt
        if isShowingRecalibrationPrompt {
            log("Already showing recalibration prompt, skipping")
            return
        }
        
        // Debounce: don't show if we just showed within 30 seconds
        let timeSinceLastPrompt = Date().timeIntervalSince(lastRecalibrationPromptTime)
        if timeSinceLastPrompt < 30 {
            log("Debouncing recalibration prompt (last shown \(String(format: "%.1f", timeSinceLastPrompt))s ago)")
            return
        }

        // Avoid repeating the same prompt for the same display/resolution
        let currentDisplayID = ScreenManager.shared.displayID
        let currentResolution = CGSize(width: ScreenManager.shared.screenFrame.width,
                                       height: ScreenManager.shared.screenFrame.height)
        if lastRecalibrationPromptDisplayID == currentDisplayID &&
            lastRecalibrationPromptResolution == currentResolution {
            log("Skipping duplicate recalibration prompt for same display/resolution")
            return
        }
        
        isShowingRecalibrationPrompt = true
        lastRecalibrationPromptTime = Date()
        lastRecalibrationPromptDisplayID = currentDisplayID
        lastRecalibrationPromptResolution = currentResolution
        
        // Use standard alert - simple and clean
        let alert = NSAlert()
        alert.messageText = "Screen Configuration Changed"
        alert.informativeText = "The display configuration has changed. You may need to recalibrate for accurate touch input."
        alert.addButton(withTitle: "Calibrate Now")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .warning
        
        let response = alert.runModal()
        isShowingRecalibrationPrompt = false
        
        if response == .alertFirstButtonReturn {
            startCalibration(mode: .basic)
        }
    }
}
