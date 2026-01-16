//
//  HIDConstants.swift
//  TouchRedirectMac
//
//  Constants for HID device and report parsing
//

import Foundation

enum HIDConstants {
    // Cisco WebEx Desk Pro
    static let vendorID: Int = 0x05a6
    static let productID: Int = 0x0b05
    
    // Usage Pages
    static let usagePageDigitizer: Int = 0x0D
    static let usagePageGenericDesktop: Int = 0x01
    
    // Digitizer Usages
    static let usageDigitizer: Int = 0x04
    static let usageTouchScreen: Int = 0x04
    
    // Report IDs
    static let touchReportID: UInt8 = 0x04
    
    // Touch element usages
    static let usageTipSwitch: Int = 0x42      // Touch down/up
    static let usageContactID: Int = 0x51      // Contact identifier
    static let usageX: Int = 0x30              // X coordinate
    static let usageY: Int = 0x31              // Y coordinate
    static let usageContactCount: Int = 0x54   // Number of contacts
    
    // Coordinate ranges (from device descriptor)
    static let logicalMaxX: Int = 16384
    static let logicalMaxY: Int = 8220
    static let logicalMinX: Int = 0
    static let logicalMinY: Int = 0
    
    // Physical units (from device descriptor, in 0.01mm)
    static let physicalMaxX: Int = 4096  // ~40.96 cm
    static let physicalMaxY: Int = 2204  // ~22.04 cm
}
