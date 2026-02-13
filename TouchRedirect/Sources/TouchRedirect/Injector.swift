//
//  Injector.swift
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
//  Injects mouse and keyboard events into macOS using CGEvent.
//  Handles cursor movement, clicks, scrolling, and system keyboard shortcuts.
//

import Foundation
import CoreGraphics
import Cocoa

// MARK: - Event Injector

/// Injects mouse events into the system using CGEvent
class Injector {
    // Track current mouse button state
    private var isMouseDown: Bool = false
    private var lastPosition: CGPoint = .zero
    
    /// Move the cursor to the specified position
    /// - Parameter position: Screen coordinates to move to
    func moveCursor(to position: CGPoint) {
        lastPosition = position
        
        let eventType: CGEventType = isMouseDown ? .leftMouseDragged : .mouseMoved
        
        if let event = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: position,
            mouseButton: .left
        ) {
            event.post(tap: .cghidEventTap)
        }
    }
    
    /// Simulate mouse button down at current position
    func mouseDown(at position: CGPoint) {
        guard !isMouseDown else { return }
        
        isMouseDown = true
        lastPosition = position
        
        if let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: position,
            mouseButton: .left
        ) {
            event.post(tap: .cghidEventTap)
        }
    }
    
    /// Simulate mouse button up at current position
    func mouseUp(at position: CGPoint) {
        guard isMouseDown else { return }
        
        isMouseDown = false
        
        if let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: position,
            mouseButton: .left
        ) {
            event.post(tap: .cghidEventTap)
        }
    }
    
    /// Simulate a right click at the specified position
    func rightClick(at position: CGPoint) {
        // Right mouse down
        if let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseDown,
            mouseCursorPosition: position,
            mouseButton: .right
        ) {
            downEvent.post(tap: .cghidEventTap)
        }
        
        // Small delay
        usleep(50000) // 50ms
        
        // Right mouse up
        if let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseUp,
            mouseCursorPosition: position,
            mouseButton: .right
        ) {
            upEvent.post(tap: .cghidEventTap)
        }
    }
    
    // Accumulated fractional scroll values
    private var accumulatedScrollX: CGFloat = 0
    private var accumulatedScrollY: CGFloat = 0
    
    /// Simulate scroll wheel events with fractional accumulation
    /// - Parameters:
    ///   - deltaX: Horizontal scroll amount (can be fractional)
    ///   - deltaY: Vertical scroll amount (can be fractional)
    func scroll(deltaX: CGFloat, deltaY: CGFloat) {
        // Accumulate fractional values
        accumulatedScrollX += deltaX
        accumulatedScrollY += deltaY
        
        // Only send when we have at least 1 pixel worth
        let scrollX = Int32(accumulatedScrollX)
        let scrollY = Int32(accumulatedScrollY)
        
        if scrollX != 0 || scrollY != 0 {
            // Subtract what we're sending from accumulator
            accumulatedScrollX -= CGFloat(scrollX)
            accumulatedScrollY -= CGFloat(scrollY)
            
            if let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: scrollY,
                wheel2: scrollX,
                wheel3: 0
            ) {
                // Set continuous scroll flag for smoother scrolling
                event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                event.post(tap: .cghidEventTap)
            }
        }
    }
    
    /// Reset scroll accumulator (call when scroll gesture ends)
    func resetScrollAccumulator() {
        accumulatedScrollX = 0
        accumulatedScrollY = 0
    }
    
    /// Check if we currently have the mouse button held down
    var isButtonDown: Bool {
        return isMouseDown
    }

    /// Returns current cursor location in CGEvent coordinate space.
    /// Falls back to the last injected position if current location is unavailable.
    func currentCursorPosition() -> CGPoint? {
        if let event = CGEvent(source: nil) {
            return event.location
        }
        return lastPosition
    }
    
    // MARK: - System Actions
    
    /// Mission Control - Launch directly as an app (most reliable)
    func missionControl() {
        log("Gesture: Mission Control triggered")
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        NSWorkspace.shared.open(url)
    }
    
    /// App Exposé - Use keyboard shortcut (Control + Down Arrow by default)
    func appExpose() {
        log("Gesture: App Exposé triggered")
        sendSystemShortcut(keyCode: 0x7D, modifiers: .maskControl) // Down arrow
    }
    
    /// Move to left desktop - Use configurable shortcut
    func moveToLeftDesktop() {
        let config = Config.shared
        let modifiers = modifiersFromString(config.desktopLeftModifiers)
        log("Gesture: Move to left desktop - keyCode=\(config.desktopLeftKeyCode), modifierStr='\(config.desktopLeftModifiers)', flags=\(modifiers.rawValue)")
        sendSystemShortcut(keyCode: CGKeyCode(config.desktopLeftKeyCode), modifiers: modifiers)
    }
    
    /// Move to right desktop - Use configurable shortcut
    func moveToRightDesktop() {
        let config = Config.shared
        let modifiers = modifiersFromString(config.desktopRightModifiers)
        log("Gesture: Move to right desktop - keyCode=\(config.desktopRightKeyCode), modifierStr='\(config.desktopRightModifiers)', flags=\(modifiers.rawValue)")
        sendSystemShortcut(keyCode: CGKeyCode(config.desktopRightKeyCode), modifiers: modifiers)
    }
    
    /// Zoom in (Command + Plus/Equals)
    func zoomIn() {
        log("Gesture: Zoom in triggered")
        sendSystemShortcut(keyCode: 0x18, modifiers: .maskCommand) // = key
    }
    
    /// Zoom out (Command + Minus)
    func zoomOut() {
        log("Gesture: Zoom out triggered")
        sendSystemShortcut(keyCode: 0x1B, modifiers: .maskCommand) // - key
    }
    
    // MARK: - Keyboard Shortcut Helper
    
    /// Send a keyboard shortcut using CGEvent
    /// Sends modifier keys separately for better system recognition
    private func sendSystemShortcut(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        // Key codes for modifier keys
        let controlKeyCode: CGKeyCode = 0x3B  // Left Control
        let shiftKeyCode: CGKeyCode = 0x38    // Left Shift
        let optionKeyCode: CGKeyCode = 0x3A   // Left Option
        let commandKeyCode: CGKeyCode = 0x37  // Left Command
        
        let tap = CGEventTapLocation.cghidEventTap
        
        // Press modifier keys first
        var pressedModifiers: [String] = []
        if modifiers.contains(.maskControl) {
            pressedModifiers.append("Control")
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: controlKeyCode, keyDown: true) {
                event.post(tap: tap)
            }
        }
        if modifiers.contains(.maskShift) {
            pressedModifiers.append("Shift")
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: shiftKeyCode, keyDown: true) {
                event.post(tap: tap)
            }
        }
        if modifiers.contains(.maskAlternate) {
            pressedModifiers.append("Option")
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: optionKeyCode, keyDown: true) {
                event.post(tap: tap)
            }
        }
        if modifiers.contains(.maskCommand) {
            pressedModifiers.append("Command")
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: commandKeyCode, keyDown: true) {
                event.post(tap: tap)
            }
        }
        log("sendSystemShortcut: pressing modifiers=[\(pressedModifiers.joined(separator: ", "))] + keyCode=\(keyCode)")
        
        usleep(20000) // 20ms for modifiers to register
        
        // Press and release the main key (don't set flags since we already pressed modifier keys)
        if let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
           let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            // Don't set flags - the modifier keys are already held down
            keyDownEvent.post(tap: tap)
            usleep(50000) // 50ms
            keyUpEvent.post(tap: tap)
        }
        
        usleep(10000) // 10ms before releasing modifiers
        
        // Release modifier keys
        if modifiers.contains(.maskCommand) {
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: commandKeyCode, keyDown: false) {
                event.post(tap: tap)
            }
        }
        if modifiers.contains(.maskAlternate) {
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: optionKeyCode, keyDown: false) {
                event.post(tap: tap)
            }
        }
        if modifiers.contains(.maskShift) {
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: shiftKeyCode, keyDown: false) {
                event.post(tap: tap)
            }
        }
        if modifiers.contains(.maskControl) {
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: controlKeyCode, keyDown: false) {
                event.post(tap: tap)
            }
        }
    }
    
    /// Convert modifier string to CGEventFlags
    private func modifiersFromString(_ modifierString: String) -> CGEventFlags {
        var flags: CGEventFlags = []
        let lower = modifierString.lowercased()
        
        if lower.contains("control") {
            flags.insert(.maskControl)
        }
        if lower.contains("command") {
            flags.insert(.maskCommand)
        }
        if lower.contains("option") || lower.contains("alt") {
            flags.insert(.maskAlternate)
        }
        if lower.contains("shift") {
            flags.insert(.maskShift)
        }
        
        return flags
    }
}
