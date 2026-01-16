//
//  EventInjector.swift
//  TouchRedirectMac
//
//  Injects mouse and scroll events into the system
//

import Foundation
import CoreGraphics

class EventInjector {
    private var lastCursorPosition: CGPoint = .zero
    
    func moveCursor(to position: CGPoint) {
        // Create mouse move event
        if let event = CGEvent(mouseEventSource: nil,
                               mouseType: .mouseMoved,
                               mouseCursorPosition: position,
                               mouseButton: .left) {
            event.post(tap: .cghidEventTap)
            lastCursorPosition = position
        }
    }
    
    func sendClick(at position: CGPoint, button: CGMouseButton, clickCount: Int = 1) {
        let mouseDown: CGEventType
        let mouseUp: CGEventType
        
        switch button {
        case .left:
            mouseDown = .leftMouseDown
            mouseUp = .leftMouseUp
        case .right:
            mouseDown = .rightMouseDown
            mouseUp = .rightMouseUp
        case .center:
            mouseDown = .otherMouseDown
            mouseUp = .otherMouseUp
        @unknown default:
            mouseDown = .leftMouseDown
            mouseUp = .leftMouseUp
        }
        
        // Mouse down
        if let downEvent = CGEvent(mouseEventSource: nil,
                                   mouseType: mouseDown,
                                   mouseCursorPosition: position,
                                   mouseButton: button) {
            downEvent.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            downEvent.post(tap: .cghidEventTap)
        }
        
        // Small delay
        usleep(10000) // 10ms
        
        // Mouse up
        if let upEvent = CGEvent(mouseEventSource: nil,
                                 mouseType: mouseUp,
                                 mouseCursorPosition: position,
                                 mouseButton: button) {
            upEvent.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            upEvent.post(tap: .cghidEventTap)
        }
    }
    
    func sendScroll(deltaY: Int32, at position: CGPoint) {
        // Create scroll wheel event
        if let scrollEvent = CGEvent(scrollWheelEvent2Source: nil,
                                     units: .pixel,
                                     wheelCount: 1,
                                     wheel1: deltaY,
                                     wheel2: 0,
                                     wheel3: 0) {
            // Set the event location
            scrollEvent.location = position
            scrollEvent.post(tap: .cghidEventTap)
        }
    }
    
    func sendDrag(from start: CGPoint, to end: CGPoint) {
        // Drag operation
        if let downEvent = CGEvent(mouseEventSource: nil,
                                   mouseType: .leftMouseDown,
                                   mouseCursorPosition: start,
                                   mouseButton: .left) {
            downEvent.post(tap: .cghidEventTap)
        }
        
        if let dragEvent = CGEvent(mouseEventSource: nil,
                                   mouseType: .leftMouseDragged,
                                   mouseCursorPosition: end,
                                   mouseButton: .left) {
            dragEvent.post(tap: .cghidEventTap)
        }
        
        if let upEvent = CGEvent(mouseEventSource: nil,
                                 mouseType: .leftMouseUp,
                                 mouseCursorPosition: end,
                                 mouseButton: .left) {
            upEvent.post(tap: .cghidEventTap)
        }
    }
}
