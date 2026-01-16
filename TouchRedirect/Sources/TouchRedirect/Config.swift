//
//  Config.swift
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
//  User preferences and calibration data storage using UserDefaults.
//

import Foundation

// MARK: - Notifications

// Notification sent when enabled state changes
extension Notification.Name {
    static let touchRedirectEnabledChanged = Notification.Name("touchRedirectEnabledChanged")
}

/// User configuration for TouchRedirect
class Config {
    static let shared = Config()
    
    private let defaults = UserDefaults.standard
    
    // Keys
    private let kInvertY = "invertY"
    private let kScrollSensitivity = "scrollSensitivity"
    private let kTapThreshold = "tapThreshold"
    private let kEnabled = "enabled"
    private let kAffineTransform = "affineTransform"
    private let kSelectedDisplayID = "selectedDisplayID"
    private let kCalibrationDisplayID = "calibrationDisplayID"
    private let kCalibrationResolution = "calibrationResolution"
    private let kLastAutoTouchDisplayID = "lastAutoTouchDisplayID"
    private let kEdgeBoostStrength = "edgeBoostStrength"
    private let kLaunchAtLogin = "launchAtLogin"
    
    // Gesture enable keys
    private let kThreeFingerSwipeEnabled = "threeFingerSwipeEnabled"
    private let kPinchToZoomEnabled = "pinchToZoomEnabled"
    private let kReverseScrollDirection = "reverseScrollDirection"
    
    // Legacy linear calibration keys (for backwards compatibility)
    private let kCalibMinX = "calibrationMinX"
    private let kCalibMaxX = "calibrationMaxX"
    private let kCalibMinY = "calibrationMinY"
    private let kCalibMaxY = "calibrationMaxY"
    
    /// Whether to invert Y axis
    var invertY: Bool {
        get { defaults.bool(forKey: kInvertY) }
        set { defaults.set(newValue, forKey: kInvertY) }
    }
    
    /// Scroll sensitivity multiplier (1.0 = normal)
    var scrollSensitivity: Double {
        get {
            let value = defaults.double(forKey: kScrollSensitivity)
            return value > 0 ? value : 1.0
        }
        set { defaults.set(newValue, forKey: kScrollSensitivity) }
    }
    
    
    /// Maximum distance (in touch units) for a tap vs drag
    var tapThreshold: Int {
        get {
            let value = defaults.integer(forKey: kTapThreshold)
            return value > 0 ? value : 50
        }
        set { defaults.set(newValue, forKey: kTapThreshold) }
    }
    
    /// Whether touch redirect is enabled
    var enabled: Bool {
        get { 
            // Default to true if not set
            if defaults.object(forKey: kEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: kEnabled) 
        }
        set { 
            let oldValue = defaults.bool(forKey: kEnabled)
            defaults.set(newValue, forKey: kEnabled)
            if oldValue != newValue {
                NotificationCenter.default.post(name: .touchRedirectEnabledChanged, object: nil)
            }
        }
    }
    
    /// Affine transform calibration data (new system)
    /// Stores: a, b, c, d, tx, ty coefficients
    var affineTransform: [String: Double]? {
        get { 
            return defaults.dictionary(forKey: kAffineTransform) as? [String: Double]
        }
        set { 
            if let value = newValue {
                defaults.set(value, forKey: kAffineTransform)
            } else {
                defaults.removeObject(forKey: kAffineTransform)
            }
        }
    }
    
    // MARK: - Legacy Linear Calibration (backwards compatibility)
    // Note: These values can be negative or zero after extrapolation,
    // so we don't apply the > 0 validation that was previously present.
    
    var calibrationMinX: Double {
        get { 
            if defaults.object(forKey: kCalibMinX) == nil {
                return 88.0  // Default only if never set
            }
            return defaults.double(forKey: kCalibMinX)
        }
        set { defaults.set(newValue, forKey: kCalibMinX) }
    }
    
    var calibrationMaxX: Double {
        get { 
            if defaults.object(forKey: kCalibMaxX) == nil {
                return 15859.0
            }
            return defaults.double(forKey: kCalibMaxX)
        }
        set { defaults.set(newValue, forKey: kCalibMaxX) }
    }
    
    var calibrationMinY: Double {
        get { 
            if defaults.object(forKey: kCalibMinY) == nil {
                return 86.0
            }
            return defaults.double(forKey: kCalibMinY)
        }
        set { defaults.set(newValue, forKey: kCalibMinY) }
    }
    
    var calibrationMaxY: Double {
        get { 
            if defaults.object(forKey: kCalibMaxY) == nil {
                return 9525.0
            }
            return defaults.double(forKey: kCalibMaxY)
        }
        set { defaults.set(newValue, forKey: kCalibMaxY) }
    }
    
    /// Clear all calibration data
    func resetAllCalibration() {
        affineTransform = nil
        calibrationDisplayID = 0
        calibrationResolution = nil
        defaults.removeObject(forKey: kCalibMinX)
        defaults.removeObject(forKey: kCalibMaxX)
        defaults.removeObject(forKey: kCalibMinY)
        defaults.removeObject(forKey: kCalibMaxY)
    }
    
    // MARK: - Display Selection
    
    /// User-selected display ID (0 = auto-detect)
    var selectedDisplayID: Int {
        get { defaults.integer(forKey: kSelectedDisplayID) }
        set { defaults.set(newValue, forKey: kSelectedDisplayID) }
    }
    
    /// Display ID that was used for calibration
    var calibrationDisplayID: Int {
        get { defaults.integer(forKey: kCalibrationDisplayID) }
        set { defaults.set(newValue, forKey: kCalibrationDisplayID) }
    }

    /// Last auto-detected touch display ID (used for reconnect scenarios)
    var lastAutoTouchDisplayID: Int {
        get { defaults.integer(forKey: kLastAutoTouchDisplayID) }
        set { defaults.set(newValue, forKey: kLastAutoTouchDisplayID) }
    }
    
    /// Resolution that was used for calibration (width, height)
    var calibrationResolution: (width: Double, height: Double)? {
        get {
            guard let dict = defaults.dictionary(forKey: kCalibrationResolution),
                  let width = dict["width"] as? Double,
                  let height = dict["height"] as? Double else {
                return nil
            }
            return (width, height)
        }
        set {
            if let res = newValue {
                defaults.set(["width": res.width, "height": res.height], forKey: kCalibrationResolution)
            } else {
                defaults.removeObject(forKey: kCalibrationResolution)
            }
        }
    }
    
    // MARK: - Edge Boost
    
    /// Edge boost strength (0.0 = none, 0.3 = strong)
    var edgeBoostStrength: Double {
        get {
            if defaults.object(forKey: kEdgeBoostStrength) == nil {
                return 0.15 // Default
            }
            return defaults.double(forKey: kEdgeBoostStrength)
        }
        set { defaults.set(newValue, forKey: kEdgeBoostStrength) }
    }
    
    // MARK: - Gesture Settings
    
    /// Whether three-finger swipe gestures are enabled
    var threeFingerSwipeEnabled: Bool {
        get {
            if defaults.object(forKey: kThreeFingerSwipeEnabled) == nil {
                return true // Default enabled
            }
            return defaults.bool(forKey: kThreeFingerSwipeEnabled)
        }
        set { defaults.set(newValue, forKey: kThreeFingerSwipeEnabled) }
    }
    
    /// Whether pinch-to-zoom gesture is enabled
    var pinchToZoomEnabled: Bool {
        get {
            if defaults.object(forKey: kPinchToZoomEnabled) == nil {
                return true // Default enabled
            }
            return defaults.bool(forKey: kPinchToZoomEnabled)
        }
        set { defaults.set(newValue, forKey: kPinchToZoomEnabled) }
    }
    
    /// Whether to reverse two-finger scroll direction
    var reverseScrollDirection: Bool {
        get { defaults.bool(forKey: kReverseScrollDirection) }
        set { defaults.set(newValue, forKey: kReverseScrollDirection) }
    }
    
    // MARK: - Desktop Switching Shortcuts
    // These allow users to customize the shortcuts to match their macOS configuration
    
    /// Key code for moving to left desktop (default: Left Arrow = 123)
    var desktopLeftKeyCode: Int {
        get {
            let value = defaults.integer(forKey: "desktopLeftKeyCode")
            return value > 0 ? value : 123 // Left Arrow
        }
        set { defaults.set(newValue, forKey: "desktopLeftKeyCode") }
    }
    
    /// Modifiers for left desktop shortcut (default: "control down")
    var desktopLeftModifiers: String {
        get {
            let value = defaults.string(forKey: "desktopLeftModifiers")
            return value ?? "control down"
        }
        set { defaults.set(newValue, forKey: "desktopLeftModifiers") }
    }
    
    /// Key code for moving to right desktop (default: Right Arrow = 124)
    var desktopRightKeyCode: Int {
        get {
            let value = defaults.integer(forKey: "desktopRightKeyCode")
            return value > 0 ? value : 124 // Right Arrow
        }
        set { defaults.set(newValue, forKey: "desktopRightKeyCode") }
    }
    
    /// Modifiers for right desktop shortcut (default: "control down")
    var desktopRightModifiers: String {
        get {
            let value = defaults.string(forKey: "desktopRightModifiers")
            return value ?? "control down"
        }
        set { defaults.set(newValue, forKey: "desktopRightModifiers") }
    }
    
    // MARK: - Launch Settings
    
    /// Whether to launch at login
    var launchAtLogin: Bool {
        get { defaults.bool(forKey: kLaunchAtLogin) }
        set { defaults.set(newValue, forKey: kLaunchAtLogin) }
    }
    
    // MARK: - Onboarding
    
    /// Whether onboarding has been completed
    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }
    
    // MARK: - Touch Activity Indicator
    
    /// Whether to show touch activity indicator in menu bar
    var showTouchActivityIndicator: Bool {
        get { defaults.bool(forKey: "showTouchActivityIndicator") }
        set { defaults.set(newValue, forKey: "showTouchActivityIndicator") }
    }
    
    private init() {}
}
