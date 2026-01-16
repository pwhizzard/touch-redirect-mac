//
//  TouchParser.swift
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
//  Parses raw HID touch reports into structured touch point data.
//  Supports multi-touch parsing for up to 5 simultaneous touch points.
//

import Foundation

// MARK: - Touch Data Structures

/// Represents a single touch point from a touch-enabled display
struct TouchPoint {
    let contactID: UInt8      // Which finger (0-9)
    let tipSwitch: Bool       // True = touching, False = lifted
    let x: UInt16             // X coordinate (0-16384)
    let y: UInt16             // Y coordinate (0-8220)
}

/// Represents a complete touch report with potentially multiple touch points
struct TouchReport {
    let contactCount: UInt8   // Number of simultaneous touches
    let touches: [TouchPoint]
}

/// Parses HID touch reports from WebEx Desk Pro
/// 
/// Report format (Report ID 0x04):
/// - Byte 0: Report ID (0x04) - already stripped by callback
/// - Byte 1: Contact ID (6 bits) + Tip Switch (bit 0)
/// - Bytes 2-3: X coordinate (16-bit little-endian, range 0-16384)
/// - Bytes 4-5: Y coordinate (16-bit little-endian, range 0-8220)
/// - Byte 6: Contact count
/// 
/// For multi-touch, additional contacts follow the same pattern
class TouchParser {
    
    /// Enable diagnostic logging for multi-touch debugging (disable for production)
    var diagnosticMode: Bool = false
    private var lastDiagnosticLog: Date = .distantPast
    private var lastTouchCount: Int = 0
    
    /// Parse a touch report from raw HID data
    /// - Parameter data: Raw bytes from HID input report (includes Report ID at byte 0)
    /// - Returns: Parsed TouchReport or nil if invalid
    func parse(data: [UInt8]) -> TouchReport? {
        // Minimum size: 1 (report ID) + 5 (touch data) = 6 bytes
        guard data.count >= 6 else {
            return nil
        }
        
        var touches: [TouchPoint] = []
        
        // Desk Pro format (56 bytes):
        // Byte 0: Report ID (0x04)
        // Byte 1: Tip Switch (bit 6) + Contact ID (bits 0-5)
        // Bytes 2-3: X coordinate (16-bit LE)
        // Bytes 4-5: Y coordinate (16-bit LE)
        // Bytes 6+: Additional touch data (format TBD)
        
        // Parse primary touch at offset 1
        if let touch = parseTouchPoint(data: data, offset: 1) {
            if touch.tipSwitch {
                touches.append(touch)
            }
        }
        
        // Check for second touch at offset 6
        if data.count >= 11 {
            let byte6 = data[6]
            if (byte6 & 0x40) != 0 {  // Tip switch is on
                if let touch = parseTouchPoint(data: data, offset: 6) {
                    if touch.tipSwitch {
                        touches.append(touch)
                    }
                }
            }
        }
        
        // Check for third touch at offset 11
        if data.count >= 16 {
            let byte11 = data[11]
            if (byte11 & 0x40) != 0 {  // Tip switch is on
                if let touch = parseTouchPoint(data: data, offset: 11) {
                    if touch.tipSwitch {
                        touches.append(touch)
                    }
                }
            }
        }
        
        // Check for fourth touch at offset 16
        if data.count >= 21 {
            let byte16 = data[16]
            if (byte16 & 0x40) != 0 {  // Tip switch is on
                if let touch = parseTouchPoint(data: data, offset: 16) {
                    if touch.tipSwitch {
                        touches.append(touch)
                    }
                }
            }
        }
        
        // Check for fifth touch at offset 21
        if data.count >= 26 {
            let byte21 = data[21]
            if (byte21 & 0x40) != 0 {  // Tip switch is on
                if let touch = parseTouchPoint(data: data, offset: 21) {
                    if touch.tipSwitch {
                        touches.append(touch)
                    }
                }
            }
        }
        
        // Diagnostic logging for multi-touch debugging
        if diagnosticMode && touches.count != lastTouchCount {
            let now = Date()
            // Log when touch count changes
            log("TouchParser: \(touches.count) active touches (report size: \(data.count) bytes)")
            if touches.count >= 2 {
                // Log first 30 bytes as hex for analysis
                let hexBytes = data.prefix(min(30, data.count)).map { String(format: "%02X", $0) }.joined(separator: " ")
                log("  Raw bytes: \(hexBytes)")
                for (i, touch) in touches.enumerated() {
                    log("  Touch[\(i)]: id=\(touch.contactID) tip=\(touch.tipSwitch) pos=(\(touch.x), \(touch.y))")
                }
            }
            lastTouchCount = touches.count
            lastDiagnosticLog = now
        }
        
        let contactCount = UInt8(touches.count)
        return TouchReport(contactCount: contactCount, touches: touches)
    }
    
    /// Parse a single touch point from the data
    /// Desk Pro format: Byte has tip switch in bit 6, contact ID in bits 0-5
    private func parseTouchPoint(data: [UInt8], offset: Int) -> TouchPoint? {
        guard offset + 5 <= data.count else {
            return nil
        }
        
        let byte0 = data[offset]
        // Desk Pro uses bit 6 for tip switch, bits 0-5 for contact ID
        let tipSwitch = (byte0 & 0x40) != 0  // Bit 6
        let contactID = byte0 & 0x3F         // Bits 0-5
        
        // X coordinate: 16-bit little-endian
        let xLow = UInt16(data[offset + 1])
        let xHigh = UInt16(data[offset + 2])
        let x = xLow | (xHigh << 8)
        
        // Y coordinate: 16-bit little-endian
        let yLow = UInt16(data[offset + 3])
        let yHigh = UInt16(data[offset + 4])
        let y = yLow | (yHigh << 8)
        
        return TouchPoint(
            contactID: contactID,
            tipSwitch: tipSwitch,
            x: x,
            y: y
        )
    }
}
