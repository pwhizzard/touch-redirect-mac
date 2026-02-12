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

    /// Source device identity (nil for legacy single-device path)
    var deviceIdentity: TouchDeviceIdentity?

    /// Resolved profile of the source device
    var profileID: TouchDeviceProfileID?

    /// Memberwise initializer with defaults for source-identity fields
    init(contactCount: UInt8, touches: [TouchPoint], deviceIdentity: TouchDeviceIdentity? = nil, profileID: TouchDeviceProfileID? = nil) {
        self.contactCount = contactCount
        self.touches = touches
        self.deviceIdentity = deviceIdentity
        self.profileID = profileID
    }
}

/// Parses HID touch reports from supported touch devices.
///
/// Desk Pro report format (Report ID 0x04):
/// - Byte 0: Report ID (0x04) - already stripped by callback
/// - Byte 1: Contact ID (6 bits) + Tip Switch (bit 6)
/// - Bytes 2-3: X coordinate (16-bit little-endian, range 0-16384)
/// - Bytes 4-5: Y coordinate (16-bit little-endian, range 0-8220)
/// - Byte 6+: Additional contacts follow same 5-byte pattern
///
/// XENEON EDGE uses the same HID digitiser report layout (confirmed USB HID spec).
/// Profile-specific constraints (e.g. max touches) are enforced by the parser.
class TouchParser {

    /// Enable diagnostic logging for multi-touch debugging (disable for production)
    var diagnosticMode: Bool = false
    private var lastDiagnosticLog: Date = .distantPast
    private var lastTouchCount: Int = 0

    // MARK: - Profile-Aware Parsing (preferred entry point)

    /// Parse a touch report using a resolved device profile and identity.
    /// - Parameters:
    ///   - data: Raw bytes from HID input report
    ///   - profile: Resolved device profile
    ///   - deviceIdentity: Stable device identity for source tracking
    /// - Returns: Parsed TouchReport tagged with source, or nil
    func parse(data: [UInt8], profile: TouchDeviceProfile, deviceIdentity: TouchDeviceIdentity) -> TouchReport? {
        guard var report = parseRaw(data: data, maxTouches: profile.maxTouches) else {
            return nil
        }
        report.deviceIdentity = deviceIdentity
        report.profileID = profile.id
        return report
    }

    // MARK: - Legacy Single-Device Parsing (backward compat)

    /// Parse a touch report from raw HID data (legacy path, no source tagging).
    /// - Parameter data: Raw bytes from HID input report (includes Report ID at byte 0)
    /// - Returns: Parsed TouchReport or nil if invalid
    func parse(data: [UInt8]) -> TouchReport? {
        return parseRaw(data: data, maxTouches: 5)
    }

    // MARK: - Core Parser

    /// Internal: parse raw touch data enforcing a max touch count.
    private func parseRaw(data: [UInt8], maxTouches: Int) -> TouchReport? {
        // Minimum size: 1 (report ID) + 5 (touch data) = 6 bytes
        guard data.count >= 6 else {
            return nil
        }

        var touches: [TouchPoint] = []

        // Touch points are packed at 5-byte intervals starting at offset 1
        let touchSlotSize = 5
        let firstOffset = 1
        let maxSlots = min(maxTouches, (data.count - firstOffset) / touchSlotSize)

        for slot in 0..<maxSlots {
            let offset = firstOffset + slot * touchSlotSize
            guard offset + touchSlotSize <= data.count else { break }

            // For slot > 0, check tip switch before parsing to match original Desk Pro behavior
            if slot > 0 {
                let byte = data[offset]
                guard (byte & 0x40) != 0 else { continue }
            }

            if let touch = parseTouchPoint(data: data, offset: offset) {
                if touch.tipSwitch {
                    touches.append(touch)
                }
            }
        }

        // Diagnostic logging for multi-touch debugging
        if diagnosticMode && touches.count != lastTouchCount {
            let now = Date()
            log("TouchParser: \(touches.count) active touches (report size: \(data.count) bytes)")
            if touches.count >= 2 {
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

    // MARK: - Touch Point Parsing

    /// Parse a single touch point from the data.
    /// Format: Byte has tip switch in bit 6, contact ID in bits 0-5,
    /// followed by X (16-bit LE) and Y (16-bit LE).
    private func parseTouchPoint(data: [UInt8], offset: Int) -> TouchPoint? {
        guard offset + 5 <= data.count else {
            return nil
        }

        let byte0 = data[offset]
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
