//
//  ScreenManager.swift
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
//  Centralized screen detection and management for multi-monitor setups.
//  Handles auto-detection, screen changes, and coordinate system helpers.
//

import Cocoa

// MARK: - Notifications

/// Notification posted when screen configuration changes significantly
extension Notification.Name {
    static let screenConfigurationDidChange = Notification.Name("TouchRedirect.screenConfigurationDidChange")
}

/// Details about a screen change event
struct ScreenChangeInfo {
    let previousDisplayID: CGDirectDisplayID
    let newDisplayID: CGDirectDisplayID
    let previousResolution: CGSize
    let newResolution: CGSize
    let resolutionChanged: Bool
    let screenChanged: Bool
    
    /// True if calibration should be invalidated
    var requiresRecalibration: Bool {
        // Recalibrate if screen changed or resolution changed significantly (>5%)
        if screenChanged { return true }
        if !resolutionChanged { return false }

        // Guard against divide-by-zero when there was no previous screen
        guard previousResolution.width > 0 && previousResolution.height > 0 else {
            return screenChanged
        }

        let widthChange = abs(newResolution.width - previousResolution.width) / previousResolution.width
        let heightChange = abs(newResolution.height - previousResolution.height) / previousResolution.height
        return widthChange > 0.05 || heightChange > 0.05
    }
}

/// Centralized screen detection and management for TouchRedirect
/// Provides consistent screen identity across calibration and runtime mapping
class ScreenManager {
    static let shared = ScreenManager()
    
    /// The target screen for touch input (the display associated with the touch device)
    private(set) var targetScreen: NSScreen?
    
    /// Cached screen properties
    private(set) var screenFrame: CGRect = .zero
    private(set) var visibleFrame: CGRect = .zero
    private(set) var screenName: String = "Unknown"
    
    /// Screen identifier for persistence (display ID is stable across reboots)
    private(set) var displayID: CGDirectDisplayID = 0
    
    /// User-selected display ID (0 = auto-detect)
    var selectedDisplayID: CGDirectDisplayID = 0 {
        didSet {
            if selectedDisplayID != oldValue {
                log("User selected display ID: \(selectedDisplayID == 0 ? "Auto" : String(selectedDisplayID))")
                updateTargetScreen()
            }
        }
    }
    
    /// List of all available screens (for UI selection)
    var availableScreens: [(id: CGDirectDisplayID, name: String, resolution: CGSize)] {
        var screens: [(id: CGDirectDisplayID, name: String, resolution: CGSize)] = []
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                screens.append((
                    id: screenNumber,
                    name: screen.localizedName,
                    resolution: CGSize(width: screen.frame.width, height: screen.frame.height)
                ))
            }
        }
        return screens
    }
    
    private init() {
        // Load user's selected display ID from config
        selectedDisplayID = CGDirectDisplayID(Config.shared.selectedDisplayID)
        
        updateTargetScreen()
        
        // Listen for screen configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Update the target screen reference
    /// Call this when screens change or at app startup
    @objc func screenConfigurationChanged() {
        refreshTargetScreen(reason: "screen configuration change")
    }

    /// Refresh target screen and notify observers if anything changes
    func refreshTargetScreen(reason: String) {
        log("Refreshing target screen (\(reason))...")
        
        let previousDisplayID = displayID
        let previousResolution = CGSize(width: screenFrame.width, height: screenFrame.height)
        
        updateTargetScreen()
        
        // Notify observers of the change
        let changeInfo = ScreenChangeInfo(
            previousDisplayID: previousDisplayID,
            newDisplayID: displayID,
            previousResolution: previousResolution,
            newResolution: CGSize(width: screenFrame.width, height: screenFrame.height),
            resolutionChanged: previousResolution.width != screenFrame.width || previousResolution.height != screenFrame.height,
            screenChanged: previousDisplayID != 0 && previousDisplayID != displayID
        )
        
        if changeInfo.resolutionChanged || changeInfo.screenChanged {
            log("Screen change detected:")
            if changeInfo.screenChanged {
                log("  Display changed: \(previousDisplayID) -> \(displayID)")
            }
            if changeInfo.resolutionChanged {
                log("  Resolution changed: \(Int(previousResolution.width))x\(Int(previousResolution.height)) -> \(Int(screenFrame.width))x\(Int(screenFrame.height))")
            }
            
            // Notify via NotificationCenter
            NotificationCenter.default.post(
                name: .screenConfigurationDidChange,
                object: self,
                userInfo: ["changeInfo": changeInfo]
            )
        }
    }
    
    /// Find and cache the target screen for touch input
    func updateTargetScreen() {
        let previousDisplayID = displayID
        
        var bestScreen: NSScreen? = nil

        func screenForID(_ id: CGDirectDisplayID) -> NSScreen? {
            for screen in NSScreen.screens {
                if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                   screenNumber == id {
                    return screen
                }
            }
            return nil
        }

        func isTouchScreenName(_ name: String) -> Bool {
            let upper = name.uppercased()
            // Check against all known profile screen keywords
            for profile in TouchDeviceProfile.allKnown {
                for keyword in profile.screenNameKeywords {
                    if upper.contains(keyword.uppercased()) {
                        return true
                    }
                }
            }
            return upper.contains("TOUCH")
        }

        func findKnownTouchScreen() -> NSScreen? {
            // Search for any known-profile screen keyword match
            for screen in NSScreen.screens {
                let name = screen.localizedName.uppercased()
                for profile in TouchDeviceProfile.allKnown {
                    for keyword in profile.screenNameKeywords {
                        if name.contains(keyword.uppercased()) {
                            return screen
                        }
                    }
                }
            }
            return nil
        }

        func findTouchNamedScreen() -> NSScreen? {
            for screen in NSScreen.screens {
                let name = screen.localizedName.uppercased()
                if name.contains("TOUCH") {
                    return screen
                }
            }
            return nil
        }

        let detectedTouchScreen = findKnownTouchScreen() ?? findTouchNamedScreen()
        
        // If user has selected a specific display, try to find it
        if selectedDisplayID != 0 {
            if let selectedScreen = screenForID(selectedDisplayID) {
                bestScreen = selectedScreen
                log("Found user-selected screen: \(selectedScreen.localizedName)")
            }
            if bestScreen == nil {
                logError("User-selected display \(selectedDisplayID) not found, falling back to auto-detect")
            }
        }
        
        // Auto-detect logic:
        // 1. If user previously calibrated a screen, try to find it by saved display ID
        // 2. Look for known touch device screens (Desk Pro, XENEON, etc.)
        // 3. Look for any screen with "TOUCH" in the name
        // 4. Fall back to main display
        if bestScreen == nil {
            // Check if we have a previously calibrated screen saved
            let lastCalibratedID = CGDirectDisplayID(Config.shared.calibrationDisplayID)
            if lastCalibratedID != 0, let calibratedScreen = screenForID(lastCalibratedID) {
                if isTouchScreenName(calibratedScreen.localizedName) || detectedTouchScreen == nil {
                    bestScreen = calibratedScreen
                    log("Auto-detected last calibrated screen: \(calibratedScreen.localizedName)")
                } else if let touchScreen = detectedTouchScreen {
                    bestScreen = touchScreen
                    log("Last calibrated screen isn't touch; preferring detected touch screen: \(touchScreen.localizedName)")
                }
            }

            // If no last calibrated screen, try the last auto-detected touch screen
            if bestScreen == nil {
                let lastAutoTouchID = CGDirectDisplayID(Config.shared.lastAutoTouchDisplayID)
                if lastAutoTouchID != 0, let lastAutoScreen = screenForID(lastAutoTouchID) {
                    bestScreen = lastAutoScreen
                    log("Auto-detected last touch screen: \(lastAutoScreen.localizedName)")
                }
            }
            
            if bestScreen == nil, let touchScreen = detectedTouchScreen {
                bestScreen = touchScreen
                log("Auto-detected touch screen: \(touchScreen.localizedName)")
            }
            
            // Fall back to main display
            if bestScreen == nil {
                bestScreen = NSScreen.main
                log("No touch screen detected, using main display")
            }
        }
        
        guard let screen = bestScreen else {
            logError("No screens available!")
            return
        }
        
        targetScreen = screen
        screenFrame = screen.frame
        visibleFrame = screen.visibleFrame
        screenName = screen.localizedName
        
        // Get display ID for this screen
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            displayID = screenNumber
        }

        // Remember the last auto-detected touch screen to recover after reconnects
        if selectedDisplayID == 0 && isTouchScreenName(screen.localizedName) {
            if displayID != 0 && Config.shared.lastAutoTouchDisplayID != Int(displayID) {
                Config.shared.lastAutoTouchDisplayID = Int(displayID)
                log("Saved last auto touch screen: \(screen.localizedName) (\(displayID))")
            }
        }
        
        log("Target screen: \(screenName)")
        log("  Display ID: \(displayID)")
        log("  Frame: \(Int(screenFrame.width))x\(Int(screenFrame.height)) at (\(Int(screenFrame.origin.x)), \(Int(screenFrame.origin.y)))")
        log("  Visible: \(Int(visibleFrame.width))x\(Int(visibleFrame.height)) at (\(Int(visibleFrame.origin.x)), \(Int(visibleFrame.origin.y)))")
        
        // Notify if screen changed
        if previousDisplayID != 0 && previousDisplayID != displayID {
            logError("Target screen changed! Calibration may need to be redone.")
        }
    }
    
    /// Select a screen by display ID (0 = auto-detect)
    func selectScreen(displayID: CGDirectDisplayID) {
        selectedDisplayID = displayID
        Config.shared.selectedDisplayID = Int(displayID)
    }
    
    /// Get the menubar height for the target screen
    var menubarHeight: CGFloat {
        return screenFrame.height - visibleFrame.height - dockHeight
    }
    
    /// Get the dock height (if dock is at bottom)
    var dockHeight: CGFloat {
        // Dock at bottom: visibleFrame.origin.y > screenFrame.origin.y
        return max(0, visibleFrame.origin.y - screenFrame.origin.y)
    }
    
    /// Check if a screen point is within the target screen bounds
    func isPointInScreen(_ point: CGPoint) -> Bool {
        return screenFrame.contains(point)
    }
    
    /// Clamp a point to screen bounds
    func clampToScreen(_ point: CGPoint) -> CGPoint {
        let x = max(screenFrame.minX, min(screenFrame.maxX - 1, point.x))
        let y = max(screenFrame.minY, min(screenFrame.maxY - 1, point.y))
        return CGPoint(x: x, y: y)
    }

    // MARK: - Per-Device Display Resolution

    /// Resolve the target display for a specific touch device.
    ///
    /// Priority order:
    /// 1. Explicit user binding (from Config `device.<key>.boundDisplayID`)
    /// 2. Auto-correlation by profile `screenNameKeywords` against connected screens
    /// 3. Fallback to the global target screen
    ///
    /// Returns an `NSScreen` and its `CGDirectDisplayID`.
    func resolveDisplay(forDeviceKey deviceKey: String,
                        profile: TouchDeviceProfile) -> (screen: NSScreen, displayID: CGDirectDisplayID) {
        let screens = NSScreen.screens

        // Helper: find NSScreen by display ID
        func screenFor(_ id: CGDirectDisplayID) -> NSScreen? {
            for s in screens {
                if let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                   num == id {
                    return s
                }
            }
            return nil
        }

        // 1. Explicit user binding
        let boundID = CGDirectDisplayID(Config.shared.boundDisplayID(forDevice: deviceKey))
        if boundID != 0, let boundScreen = screenFor(boundID) {
            return (boundScreen, boundID)
        }

        // 2. Auto-correlation via profile screen-name keywords
        if !profile.screenNameKeywords.isEmpty {
            for screen in screens {
                let upper = screen.localizedName.uppercased()
                for keyword in profile.screenNameKeywords {
                    if upper.contains(keyword.uppercased()) {
                        if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                            return (screen, id)
                        }
                    }
                }
            }
        }

        // 3. Fallback to global target screen
        if let ts = targetScreen {
            return (ts, displayID)
        }
        return (NSScreen.main ?? screens[0], CGMainDisplayID())
    }
}
