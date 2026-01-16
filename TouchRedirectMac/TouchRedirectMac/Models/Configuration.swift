//
//  Configuration.swift
//  TouchRedirectMac
//
//  App configuration and persistence
//

import Foundation
import CoreGraphics

struct CalibrationData: Codable {
    var offsetX: CGFloat = 0.0
    var offsetY: CGFloat = 0.0
    var scaleX: CGFloat = 1.0
    var scaleY: CGFloat = 1.0
}

class Configuration: ObservableObject {
    @Published var enabled: Bool = true
    @Published var debugMode: Bool = false
    @Published var cursorSensitivity: Double = 1.0
    @Published var scrollSensitivity: Double = 1.0
    @Published var twoFingerTapForRightClick: Bool = true
    @Published var threeFingerTapForMiddleClick: Bool = false
    @Published var launchAtLogin: Bool = false
    @Published var calibration: CalibrationData?
    @Published var targetDisplayID: CGDirectDisplayID?
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let enabled = "TouchRedirect.enabled"
        static let debugMode = "TouchRedirect.debugMode"
        static let cursorSensitivity = "TouchRedirect.cursorSensitivity"
        static let scrollSensitivity = "TouchRedirect.scrollSensitivity"
        static let twoFingerTapForRightClick = "TouchRedirect.twoFingerTapForRightClick"
        static let threeFingerTapForMiddleClick = "TouchRedirect.threeFingerTapForMiddleClick"
        static let launchAtLogin = "TouchRedirect.launchAtLogin"
        static let calibrationData = "TouchRedirect.calibrationData"
        static let targetDisplayID = "TouchRedirect.targetDisplayID"
    }
    
    init() {
        load()
    }
    
    func load() {
        enabled = defaults.bool(forKey: Keys.enabled) 
        if defaults.object(forKey: Keys.enabled) == nil {
            enabled = true // Default to enabled
        }
        
        debugMode = defaults.bool(forKey: Keys.debugMode)
        cursorSensitivity = defaults.double(forKey: Keys.cursorSensitivity)
        if cursorSensitivity == 0 { cursorSensitivity = 1.0 }
        
        scrollSensitivity = defaults.double(forKey: Keys.scrollSensitivity)
        if scrollSensitivity == 0 { scrollSensitivity = 1.0 }
        
        twoFingerTapForRightClick = defaults.bool(forKey: Keys.twoFingerTapForRightClick)
        if defaults.object(forKey: Keys.twoFingerTapForRightClick) == nil {
            twoFingerTapForRightClick = true
        }
        
        threeFingerTapForMiddleClick = defaults.bool(forKey: Keys.threeFingerTapForMiddleClick)
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        
        if let calibrationData = defaults.data(forKey: Keys.calibrationData),
           let decoded = try? JSONDecoder().decode(CalibrationData.self, from: calibrationData) {
            calibration = decoded
        }
        
        if let displayID = defaults.object(forKey: Keys.targetDisplayID) as? UInt32 {
            targetDisplayID = displayID
        }
    }
    
    func save() {
        defaults.set(enabled, forKey: Keys.enabled)
        defaults.set(debugMode, forKey: Keys.debugMode)
        defaults.set(cursorSensitivity, forKey: Keys.cursorSensitivity)
        defaults.set(scrollSensitivity, forKey: Keys.scrollSensitivity)
        defaults.set(twoFingerTapForRightClick, forKey: Keys.twoFingerTapForRightClick)
        defaults.set(threeFingerTapForMiddleClick, forKey: Keys.threeFingerTapForMiddleClick)
        defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        
        if let calibration = calibration,
           let encoded = try? JSONEncoder().encode(calibration) {
            defaults.set(encoded, forKey: Keys.calibrationData)
        }
        
        if let displayID = targetDisplayID {
            defaults.set(displayID, forKey: Keys.targetDisplayID)
        }
        
        defaults.synchronize()
    }
    
    func resetCalibration() {
        calibration = nil
        defaults.removeObject(forKey: Keys.calibrationData)
        defaults.synchronize()
    }
}
