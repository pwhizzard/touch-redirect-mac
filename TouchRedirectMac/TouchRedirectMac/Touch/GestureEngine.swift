//
//  GestureEngine.swift
//  TouchRedirectMac
//
//  Recognizes multi-touch gestures
//

import Foundation
import CoreGraphics

class GestureEngine {
    private let configuration: Configuration
    private let eventInjector: EventInjector
    
    private var lastTouchCount: Int = 0
    private var primaryTouch: TouchPoint?
    private var lastPosition: CGPoint = .zero
    private var isMouseDown: Bool = false
    private var lastClickTime: Date = Date.distantPast
    private var scrollMomentum: CGPoint = .zero
    
    init(configuration: Configuration, eventInjector: EventInjector) {
        self.configuration = configuration
        self.eventInjector = eventInjector
    }
    
    func processTouches(_ touches: [TouchPoint]) {
        let touchCount = touches.count
        let activeTouches = touches.filter { $0.isActive }
        
        if activeTouches.isEmpty {
            // All touches released
            handleTouchesEnded()
            lastTouchCount = 0
            primaryTouch = nil
            return
        }
        
        // Get primary touch (lowest ID)
        let primary = activeTouches.min(by: { $0.id < $1.id })!
        let currentPosition = CGPoint(x: primary.x, y: primary.y)
        
        switch activeTouches.count {
        case 1:
            handleSingleTouch(touch: primary, position: currentPosition)
        case 2:
            handleTwoFingerGesture(touches: activeTouches)
        default:
            handleMultiFingerGesture(touches: activeTouches)
        }
        
        lastTouchCount = touchCount
        primaryTouch = primary
        lastPosition = currentPosition
    }
    
    private func handleSingleTouch(touch: TouchPoint, position: CGPoint) {
        // Move cursor
        eventInjector.moveCursor(to: position)
        
        // Handle click (touch down/up)
        if touch.isActive && !isMouseDown {
            // Check for double-click
            let timeSinceLastClick = Date().timeIntervalSince(lastClickTime)
            if timeSinceLastClick < 0.3 {
                eventInjector.sendClick(at: position, button: .left, clickCount: 2)
            }
            
            isMouseDown = true
        }
    }
    
    private func handleTouchesEnded() {
        if isMouseDown {
            // Perform click at last position
            eventInjector.sendClick(at: lastPosition, button: .left, clickCount: 1)
            lastClickTime = Date()
            isMouseDown = false
        }
    }
    
    private func handleTwoFingerGesture(touches: [TouchPoint]) {
        guard touches.count == 2 else { return }
        
        let touch1 = touches[0]
        let touch2 = touches[1]
        
        // Calculate center point
        let centerX = (touch1.x + touch2.x) / 2
        let centerY = (touch1.y + touch2.y) / 2
        let center = CGPoint(x: centerX, y: centerY)
        
        if lastTouchCount == 2 {
            // Two finger scroll
            let deltaX = center.x - lastPosition.x
            let deltaY = center.y - lastPosition.y
            
            if abs(deltaX) > 2 || abs(deltaY) > 2 {
                let scrollAmount = Int32(deltaY * configuration.scrollSensitivity)
                eventInjector.sendScroll(deltaY: scrollAmount, at: center)
            }
        } else {
            // Just started two finger gesture
            if configuration.twoFingerTapForRightClick {
                // Right click at center
                eventInjector.sendClick(at: center, button: .right, clickCount: 1)
            }
        }
        
        lastPosition = center
    }
    
    private func handleMultiFingerGesture(touches: [TouchPoint]) {
        // Calculate center of all touches
        let centerX = touches.reduce(0.0) { $0 + $1.x } / CGFloat(touches.count)
        let centerY = touches.reduce(0.0) { $0 + $1.y } / CGFloat(touches.count)
        let center = CGPoint(x: centerX, y: centerY)
        
        // Three finger tap = middle click (if configured)
        if touches.count == 3 && lastTouchCount != 3 {
            if configuration.threeFingerTapForMiddleClick {
                eventInjector.sendClick(at: center, button: .center, clickCount: 1)
            }
        }
    }
}
