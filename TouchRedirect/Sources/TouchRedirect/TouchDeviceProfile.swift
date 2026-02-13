//
//  TouchDeviceProfile.swift
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
//  Device profile model and resolver for supported touch devices.
//  Defines capabilities, matching rules, and defaults per device type.
//

import Foundation

// MARK: - Profile Identifier

/// Identifies a known touch device profile
enum TouchDeviceProfileID: String, Codable, CaseIterable {
    case deskPro = "deskPro"
    case xeneonEdge = "xeneonEdge"
    case unknown = "unknown"
}

// MARK: - Device Profile

/// Describes a supported touch device's capabilities, matching rules, and defaults
struct TouchDeviceProfile {
    let id: TouchDeviceProfileID
    let displayName: String

    // --- Matching rules ---

    /// VID/PID pairs that identify this device
    let vendorProductPairs: [(vendorID: Int, productID: Int)]

    /// Product or manufacturer name substrings (case-insensitive) used as fallback matching
    let nameKeywords: [String]

    // --- Capabilities ---

    /// Maximum simultaneous touch points the device reports
    let maxTouches: Int

    /// Expected HID report size in bytes (0 = accept any)
    let expectedReportSize: Int

    // --- Default ranges ---

    /// Default touch coordinate ranges (used before calibration)
    let defaultMinX: CGFloat
    let defaultMaxX: CGFloat
    let defaultMinY: CGFloat
    let defaultMaxY: CGFloat

    // --- Report identification ---

    /// HID report IDs that carry touch data for this device.
    /// The HID manager will only parse reports whose ID is in this set.
    /// An empty set means "accept any report ID" (useful for unknown devices).
    let touchReportIDs: Set<UInt32>

    // --- Behavior defaults ---

    /// Whether right-edge boost compensation is enabled by default
    let defaultEdgeCompensation: Bool

    /// Screen name keywords for auto-detect heuristic
    let screenNameKeywords: [String]

    // --- Report parsing format ---

    /// Bit position of the Tip Switch flag within the first byte of each touch slot.
    /// Desk Pro uses bit 6 (0x40), Xeneon uses bit 0 (0x01).
    let tipSwitchBit: Int

    /// Bitmask to extract the Contact ID from the first byte of each touch slot.
    /// Desk Pro: 0x3F (bits 0-5), Xeneon: 0xFC (bits 2-7) then shift right by contactIDShift.
    let contactIDMask: UInt8

    /// Right-shift amount for extracting Contact ID after applying mask.
    let contactIDShift: Int
}

// MARK: - Known Profiles

extension TouchDeviceProfile {

    /// Cisco WebEx Desk Pro touch interface
    static let deskPro = TouchDeviceProfile(
        id: .deskPro,
        displayName: "Cisco WebEx Desk Pro",
        vendorProductPairs: [(vendorID: 0x05a6, productID: 0x0b05)],
        nameKeywords: ["CISCO", "WEBEX", "DESKPRO", "DESK PRO"],
        maxTouches: 5,
        expectedReportSize: 64,
        defaultMinX: 88.0,
        defaultMaxX: 15859.0,
        defaultMinY: 86.0,
        defaultMaxY: 9525.0,
        touchReportIDs: [0x04],
        defaultEdgeCompensation: true,
        screenNameKeywords: ["DESKPRO", "CISCO", "WEBEX"],
        tipSwitchBit: 6,        // Tip Switch at bit 6 of first touch byte
        contactIDMask: 0x3F,    // Contact ID in bits 0-5
        contactIDShift: 0
    )

    /// Corsair XENEON EDGE touch monitor
    static let xeneonEdge = TouchDeviceProfile(
        id: .xeneonEdge,
        displayName: "Corsair XENEON EDGE",
        vendorProductPairs: [(vendorID: 0x27C0, productID: 0x0859), (vendorID: 0x1B1C, productID: 0x1B96)],
        nameKeywords: ["CORSAIR", "XENEON", "XENEON EDGE"],
        maxTouches: 5,
        expectedReportSize: 0,  // Accept any until confirmed from hardware capture
        defaultMinX: 0.0,
        defaultMaxX: 16384.0,
        defaultMinY: 0.0,
        defaultMaxY: 16384.0,
        touchReportIDs: [],  // Accept any report ID until confirmed from hardware capture
        defaultEdgeCompensation: false,
        screenNameKeywords: ["XENEON", "CORSAIR"],
        tipSwitchBit: 0,        // Tip Switch at bit 0 (standard HID digitizer layout)
        contactIDMask: 0xFC,    // Contact ID in bits 2-7
        contactIDShift: 2
    )

    /// Fallback profile for unrecognised touch digitisers
    static let unknown = TouchDeviceProfile(
        id: .unknown,
        displayName: "Unknown Touch Device",
        vendorProductPairs: [],
        nameKeywords: [],
        maxTouches: 10,
        expectedReportSize: 0,
        defaultMinX: 0.0,
        defaultMaxX: 16384.0,
        defaultMinY: 0.0,
        defaultMaxY: 16384.0,
        touchReportIDs: [],  // Accept any report ID
        defaultEdgeCompensation: false,
        screenNameKeywords: [],
        tipSwitchBit: 6,        // Default to Desk Pro layout for unknown devices
        contactIDMask: 0x3F,
        contactIDShift: 0
    )

    /// All known profiles in priority order (most specific first)
    static let allKnown: [TouchDeviceProfile] = [.deskPro, .xeneonEdge]

    /// Look up a profile by its ID. Returns `.unknown` for unrecognized IDs.
    static func profile(for id: TouchDeviceProfileID) -> TouchDeviceProfile {
        switch id {
        case .deskPro: return .deskPro
        case .xeneonEdge: return .xeneonEdge
        case .unknown: return .unknown
        }
    }
}

// MARK: - Profile Resolver

/// Central resolver for matching HID device metadata to a profile
struct TouchDeviceProfileResolver {

    /// Resolve profile by VID/PID first, then fall back to name keyword matching.
    /// Returns `.unknown` if no known profile matches.
    static func resolve(
        vendorID: Int,
        productID: Int,
        productName: String = "",
        manufacturer: String = ""
    ) -> TouchDeviceProfile {
        // Priority 1: exact VID/PID match
        for profile in TouchDeviceProfile.allKnown {
            for pair in profile.vendorProductPairs {
                if pair.vendorID == vendorID && pair.productID == productID {
                    return profile
                }
            }
        }

        // Priority 2: name keyword match (case-insensitive)
        let combinedName = "\(productName) \(manufacturer)".uppercased()
        for profile in TouchDeviceProfile.allKnown {
            for keyword in profile.nameKeywords {
                if combinedName.contains(keyword.uppercased()) {
                    return profile
                }
            }
        }

        return .unknown
    }

    /// Check whether a given HID interface is a touch digitiser
    static func isTouchDigitizer(usagePage: Int, usage: Int) -> Bool {
        return usagePage == 0x0D && usage == 0x04  // Digitizer / Touch Screen
    }

    /// Check whether a non-digitizer HID interface is a companion to a known touch device.
    /// Some touch devices (e.g. Corsair XENEON EDGE) expose a Mouse interface that macOS
    /// handles natively for single-touch cursor movement. We need to seize these to take
    /// full control. Only returns true for Mouse interfaces whose VID/PID matches a known
    /// touch device profile -- never seizes unrelated mice, trackpads, etc.
    static func isCompanionInterface(usagePage: Int, usage: Int, vendorID: Int, productID: Int) -> Bool {
        // Only consider Generic Desktop / Mouse interfaces
        guard usagePage == 0x01 && usage == 0x02 else { return false }

        // Only match if VID/PID belongs to a known touch device
        for profile in TouchDeviceProfile.allKnown {
            for pair in profile.vendorProductPairs {
                if pair.vendorID == vendorID && pair.productID == productID {
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - Stable Device Identity

/// A stable identity for a connected touch device, used as dictionary key
struct TouchDeviceIdentity: Hashable, CustomStringConvertible {
    let vendorID: Int
    let productID: Int
    let locationID: Int

    var description: String {
        let vid = String(format: "0x%04X", vendorID)
        let pid = String(format: "0x%04X", productID)
        return "\(vid):\(pid)@\(locationID)"
    }

    /// Persistence-safe string key for UserDefaults namespacing
    var persistenceKey: String {
        return "\(vendorID)_\(productID)_\(locationID)"
    }
}
