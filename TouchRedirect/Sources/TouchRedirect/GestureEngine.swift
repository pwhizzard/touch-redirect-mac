//
//  GestureEngine.swift
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
//  Interprets multi-touch input and translates it into system events.
//  Supports single-touch, two-finger scroll, three-finger swipes, and pinch-to-zoom.
//

import Foundation
import CoreGraphics

// MARK: - Gesture Engine

/// Handles multi-touch gesture recognition
class GestureEngine {
    private let mapper: Mapper
    private let injector: Injector
    private let config = Config.shared
    
    // Touch state tracking
    private var activeTouches: [UInt8: TouchState] = [:]
    private var gestureState: GestureState = .none
    
    // Timing for tap detection
    private var touchStartTime: Date?
    private let tapMaxDuration: TimeInterval = 0.3  // 300ms max for a tap
    
    // Last known position for single touch (used for mouse up)
    private var lastSingleTouchPosition: CGPoint = .zero
    
    // Three-finger swipe tracking
    private var threeFingerStartCenter: CGPoint = .zero
    private var threeFingerSwipeTriggered: Bool = false
    private let threeFingerSwipeThreshold: CGFloat = 50 // Pixels to trigger swipe (lowered for responsiveness)
    
    // Pinch tracking
    private var pinchStartDistance: CGFloat = 0
    private var pinchLastDistance: CGFloat = 0
    private var pinchZoomTriggered: Bool = false
    private let pinchThreshold: CGFloat = 50 // Pixel change to trigger zoom
    
    // Gesture stabilization - prevents spurious mouse events when fingers are still landing
    private var gestureStabilizationTime: Date?
    private let gestureStabilizationDelay: TimeInterval = 0.05 // 50ms to wait for more fingers
    private var pendingSingleTouchPosition: CGPoint?
    
    enum GestureState {
        case none
        case singleTouch
        case twoFingerScroll
        case potentialTwoFingerTap
        case threeFingerSwipe
        case potentialPinch
        case pinchZoom
    }
    
    struct TouchState {
        var startPosition: CGPoint
        var currentPosition: CGPoint
        var isActive: Bool
    }
    
    init(mapper: Mapper, injector: Injector) {
        self.mapper = mapper
        self.injector = injector
    }
    
    /// Process a touch report and generate appropriate mouse events
    func processTouchReport(_ report: TouchReport) {
        guard config.enabled else { 
            // Log once when disabled
            return 
        }
        
        // Update touch states
        var currentTouchIDs = Set<UInt8>()
        
        for touch in report.touches {
            let screenPos = mapper.mapToScreen(touchX: touch.x, touchY: touch.y)
            currentTouchIDs.insert(touch.contactID)
            
            if touch.tipSwitch {
                if var state = activeTouches[touch.contactID] {
                    // Update existing touch
                    state.currentPosition = screenPos
                    activeTouches[touch.contactID] = state
                } else {
                    // New touch - log raw coordinates for debugging
                    log("NEW TOUCH: raw=(\(touch.x), \(touch.y)) -> screen=(\(Int(screenPos.x)), \(Int(screenPos.y)))")
                    
                    activeTouches[touch.contactID] = TouchState(
                        startPosition: screenPos,
                        currentPosition: screenPos,
                        isActive: true
                    )
                    
                    // Record start time for first touch
                    if activeTouches.count == 1 {
                        touchStartTime = Date()
                    }
                }
            }
        }
        
        // Remove touches that are no longer present
        for touchID in activeTouches.keys {
            if !currentTouchIDs.contains(touchID) {
                activeTouches.removeValue(forKey: touchID)
            } else if let touch = report.touches.first(where: { $0.contactID == touchID }), !touch.tipSwitch {
                activeTouches.removeValue(forKey: touchID)
            }
        }
        
        // Determine gesture based on active touch count
        let touchCount = activeTouches.count
        let activeTipsCount = report.touches.filter { $0.tipSwitch }.count
        
        // Debug: log touch count changes
        if touchCount == 0 && gestureState != .none {
            log("processTouchReport: 0 active touches (tips in report: \(activeTipsCount)), state=\(gestureState)")
        }
        
        switch touchCount {
        case 0:
            handleNoTouches()
        case 1:
            handleSingleTouch()
        case 2:
            handleTwoFingerGesture()
        case 3:
            // If we were scrolling with two fingers, stop accumulating scroll
            if gestureState == .twoFingerScroll {
                injector.resetScrollAccumulator()
            }
            handleThreeFingerGesture()
        default:
            // 4+ fingers - could add more gestures later
            break
        }
    }
    
    private func handleNoTouches() {
        // Reset stabilization
        gestureStabilizationTime = nil
        pendingSingleTouchPosition = nil
        
        // Only log if we're transitioning from an active state
        if gestureState != .none {
            log("Touch END (was \(gestureState))")
        }
        
        // Check if this was a two-finger tap
        if gestureState == .potentialTwoFingerTap {
            if let startTime = touchStartTime,
               Date().timeIntervalSince(startTime) < tapMaxDuration {
                // It was a quick two-finger tap - right click
                injector.rightClick(at: twoFingerStartCenter)
            }
        }
        
        // Reset scroll accumulator when scroll gesture ends
        if gestureState == .twoFingerScroll {
            injector.resetScrollAccumulator()
        }
        
        // Release any held mouse button
        if injector.isButtonDown {
            log("Releasing mouse button at (\(Int(lastSingleTouchPosition.x)), \(Int(lastSingleTouchPosition.y)))")
            injector.mouseUp(at: lastSingleTouchPosition)
        }
        
        // Reset three-finger tracking
        threeFingerSwipeTriggered = false
        
        // Reset pinch tracking
        pinchZoomTriggered = false
        
        gestureState = .none
        touchStartTime = nil
    }
    
    private var lastLogTime: Date = Date.distantPast
    
    private func handleSingleTouch() {
        guard let (_, touch) = activeTouches.first else { return }
        
        // If we were in a three-finger gesture, don't start a single touch drag
        // (prevents accidental click when lifting from multi-touch)
        if gestureState == .threeFingerSwipe {
            return
        }
        
        // Always track last position for mouse up
        lastSingleTouchPosition = touch.currentPosition
        
        if gestureState != .singleTouch {
            // Wait briefly before committing to single touch (allow multi-touch to land)
            if gestureStabilizationTime == nil {
                gestureStabilizationTime = Date()
                pendingSingleTouchPosition = touch.currentPosition
                return // Wait for stabilization
            }
            
            if Date().timeIntervalSince(gestureStabilizationTime!) < gestureStabilizationDelay {
                // Still stabilizing - update position but don't commit
                pendingSingleTouchPosition = touch.currentPosition
                return
            }
            
            // Stabilization complete - commit to single touch
            log("Single touch START at (\(Int(touch.currentPosition.x)), \(Int(touch.currentPosition.y)))")
            gestureState = .singleTouch
            gestureStabilizationTime = nil
            pendingSingleTouchPosition = nil
            injector.mouseDown(at: touch.currentPosition)
        } else {
            // Continue dragging - log occasionally
            if Date().timeIntervalSince(lastLogTime) > 1.0 {
                log("Single touch DRAG at (\(Int(touch.currentPosition.x)), \(Int(touch.currentPosition.y)))")
                lastLogTime = Date()
            }
            injector.moveCursor(to: touch.currentPosition)
        }
    }
    
    private func handleTwoFingerGesture() {
        let touches = Array(activeTouches.values)
        guard touches.count == 2 else { return }
        
        // Cancel any pending single-touch (more fingers landed)
        gestureStabilizationTime = nil
        pendingSingleTouchPosition = nil
        
        // If we were in a three-finger gesture, don't overwrite it
        // (allows for momentary finger lift during swipe)
        if gestureState == .threeFingerSwipe {
            return
        }
        
        // Calculate center point
        let center = CGPoint(
            x: (touches[0].currentPosition.x + touches[1].currentPosition.x) / 2,
            y: (touches[0].currentPosition.y + touches[1].currentPosition.y) / 2
        )
        
        if gestureState != .twoFingerScroll && gestureState != .potentialTwoFingerTap && 
           gestureState != .potentialPinch && gestureState != .pinchZoom {
            // Starting two-finger gesture
            gestureState = .potentialTwoFingerTap
            
            // Initialize pinch tracking
            let dx = touches[0].currentPosition.x - touches[1].currentPosition.x
            let dy = touches[0].currentPosition.y - touches[1].currentPosition.y
            pinchStartDistance = sqrt(dx * dx + dy * dy)
            pinchLastDistance = pinchStartDistance
            pinchZoomTriggered = false
            
            // Release any mouse button from single touch
            if injector.isButtonDown {
                injector.mouseUp(at: center)
            }
            
            // Reset scroll accumulator for fresh start
            injector.resetScrollAccumulator()
            
            // Store initial positions using center point for stability
            twoFingerStartCenter = center
            previousScrollCenter = center
        } else {
            // Check for pinch gesture first (if enabled)
            if config.pinchToZoomEnabled && gestureState != .twoFingerScroll {
                let dx = touches[0].currentPosition.x - touches[1].currentPosition.x
                let dy = touches[0].currentPosition.y - touches[1].currentPosition.y
                let currentDistance = sqrt(dx * dx + dy * dy)
                let distanceChange = currentDistance - pinchStartDistance
                
                if abs(distanceChange) > pinchThreshold {
                    gestureState = .pinchZoom
                    
                    if !pinchZoomTriggered {
                        pinchZoomTriggered = true
                        
                        if distanceChange > 0 {
                            log("Pinch OUT detected - zooming in")
                            injector.zoomIn()
                        } else {
                            log("Pinch IN detected - zooming out")
                            injector.zoomOut()
                        }
                    }
                    
                    // Reset for continuous pinch detection
                    pinchStartDistance = currentDistance
                    pinchZoomTriggered = false // Allow another zoom
                    return
                }
            }
            
            // If not pinching, handle as scroll
            let deltaX = center.x - previousScrollCenter.x
            let deltaY = center.y - previousScrollCenter.y
            let movement = sqrt(deltaX * deltaX + deltaY * deltaY)
            
            // Lower threshold (3px) to start scrolling sooner
            if movement > 3 || gestureState == .twoFingerScroll {
                gestureState = .twoFingerScroll
                
                // Apply sensitivity (default 1.5 for better feel)
                let sensitivity = CGFloat(config.scrollSensitivity) * 1.5
                
                // Natural scrolling by default, reversed if user preference is set
                let direction: CGFloat = config.reverseScrollDirection ? 1.0 : -1.0
                let scrollX = deltaX * sensitivity * direction
                let scrollY = deltaY * sensitivity * direction
                
                // Send scroll with fractional accumulation
                injector.scroll(deltaX: scrollX, deltaY: scrollY)
            }
            
            // Always update previous center
            previousScrollCenter = center
        }
    }
    
    // Two-finger gesture tracking
    private var twoFingerStartCenter: CGPoint = .zero
    private var previousScrollCenter: CGPoint = .zero
    
    // MARK: - Three-Finger Gestures
    
    private func handleThreeFingerGesture() {
        guard config.threeFingerSwipeEnabled else { return }
        
        let touches = Array(activeTouches.values)
        guard touches.count >= 3 else { return }
        
        // Cancel any pending single-touch (more fingers landed)
        gestureStabilizationTime = nil
        pendingSingleTouchPosition = nil
        
        // Calculate center of all touches (use first 3)
        let touchesToUse = Array(touches.prefix(3))
        let center = CGPoint(
            x: touchesToUse.reduce(0) { $0 + $1.currentPosition.x } / CGFloat(touchesToUse.count),
            y: touchesToUse.reduce(0) { $0 + $1.currentPosition.y } / CGFloat(touchesToUse.count)
        )
        
        if gestureState != .threeFingerSwipe {
            // Starting three-finger gesture
            log("Three-finger gesture START at (\(Int(center.x)), \(Int(center.y)))")
            gestureState = .threeFingerSwipe
            injector.resetScrollAccumulator()
            pinchZoomTriggered = false
            threeFingerStartCenter = center
            threeFingerSwipeTriggered = false
            
            // Release any mouse button
            if injector.isButtonDown {
                injector.mouseUp(at: center)
            }
        } else if !threeFingerSwipeTriggered {
            // Check for swipe direction
            let deltaX = center.x - threeFingerStartCenter.x
            let deltaY = center.y - threeFingerStartCenter.y
            
            let absX = abs(deltaX)
            let absY = abs(deltaY)
            
            // Log movement for debugging
            if absX > 10 || absY > 10 {
                log("Three-finger MOVE: delta=(\(Int(deltaX)), \(Int(deltaY))) threshold=\(Int(threeFingerSwipeThreshold))")
            }
            
            // Determine dominant direction
            if absX > threeFingerSwipeThreshold || absY > threeFingerSwipeThreshold {
                threeFingerSwipeTriggered = true
                
                if absX > absY {
                    // Horizontal swipe
                    if deltaX > 0 {
                        log("Three-finger swipe RIGHT detected")
                        injector.moveToRightDesktop()
                    } else {
                        log("Three-finger swipe LEFT detected")
                        injector.moveToLeftDesktop()
                    }
                } else {
                    // Vertical swipe
                    if deltaY < 0 {
                        // Swipe up (Y decreases upward in screen coords)
                        log("Three-finger swipe UP detected")
                        injector.missionControl()
                    } else {
                        log("Three-finger swipe DOWN detected")
                        injector.appExpose()
                    }
                }
            }
        }
    }
}
