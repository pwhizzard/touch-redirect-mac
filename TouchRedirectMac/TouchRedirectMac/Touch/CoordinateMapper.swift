//
//  CoordinateMapper.swift
//  TouchRedirectMac
//
//  Maps touch coordinates to screen coordinates
//

import Foundation
import CoreGraphics
import AppKit

class CoordinateMapper {
    private let configuration: Configuration
    
    init(configuration: Configuration) {
        self.configuration = configuration
    }
    
    func mapToScreen(_ point: CGPoint) -> CGPoint {
        // Get the logical max from HID device
        let logicalMaxX = CGFloat(HIDConstants.logicalMaxX)
        let logicalMaxY = CGFloat(HIDConstants.logicalMaxY)
        
        // Normalize to 0.0 - 1.0
        let normalizedX = point.x / logicalMaxX
        let normalizedY = point.y / logicalMaxY
        
        // Determine target screen
        let targetScreen = getTargetScreen()
        let screenFrame = targetScreen.frame
        
        // Apply calibration offsets if set
        var offsetX = normalizedX
        var offsetY = normalizedY
        
        if let calibration = configuration.calibration {
            offsetX = (normalizedX - calibration.offsetX) / calibration.scaleX
            offsetY = (normalizedY - calibration.offsetY) / calibration.scaleY
            offsetX = max(0, min(1, offsetX))
            offsetY = max(0, min(1, offsetY))
        }
        
        // Map to screen coordinates
        // Note: macOS origin is bottom-left, so we need to invert Y
        let screenX = screenFrame.origin.x + (offsetX * screenFrame.width)
        let screenY = screenFrame.origin.y + screenFrame.height - (offsetY * screenFrame.height)
        
        // Apply sensitivity
        return CGPoint(x: screenX, y: screenY)
    }
    
    private func getTargetScreen() -> NSScreen {
        // If a specific display is configured, use it
        if let targetDisplayID = configuration.targetDisplayID {
            for screen in NSScreen.screens {
                if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                   screenNumber == targetDisplayID {
                    return screen
                }
            }
        }
        
        // Default to main screen
        return NSScreen.main ?? NSScreen.screens[0]
    }
    
    func calibratePoint(_ normalizedPoint: CGPoint, screenPoint: CGPoint) {
        // Helper for calibration - maps a known touch point to screen point
        let screen = getTargetScreen()
        let screenFrame = screen.frame
        
        let targetNormalizedX = (screenPoint.x - screenFrame.origin.x) / screenFrame.width
        let targetNormalizedY = 1.0 - ((screenPoint.y - screenFrame.origin.y) / screenFrame.height)
        
        // Calculate offset
        let offsetX = normalizedPoint.x - targetNormalizedX
        let offsetY = normalizedPoint.y - targetNormalizedY
        
        print("Calibration: offset=(\(offsetX), \(offsetY))")
    }
}
