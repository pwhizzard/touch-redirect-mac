//
//  TouchReportParser.swift
//  TouchRedirectMac
//
//  Parses HID touch reports and extracts touch data
//

import Foundation
import CoreGraphics

class TouchReportParser {
    private let configuration: Configuration
    private let eventInjector: EventInjector
    private let coordinateMapper: CoordinateMapper
    private let gestureEngine: GestureEngine
    private var activeContacts: [Int: TouchPoint] = [:]
    
    init(configuration: Configuration, eventInjector: EventInjector) {
        self.configuration = configuration
        self.eventInjector = eventInjector
        self.coordinateMapper = CoordinateMapper(configuration: configuration)
        self.gestureEngine = GestureEngine(configuration: configuration, eventInjector: eventInjector)
    }
    
    func parseReport(reportID: UInt8, data: Data) {
        // Only process touch reports
        guard reportID == HIDConstants.touchReportID else {
            return
        }
        
        guard data.count >= 7 else {
            return
        }
        
        // Parse report structure based on device descriptor:
        // Byte 0: Report ID (0x04)
        // Byte 1: Contact ID (6 bits) + Tip Switch (1 bit) + padding
        // Bytes 2-3: X coordinate (16 bits, little endian)
        // Bytes 4-5: Y coordinate (16 bits, little endian)
        // Byte 6: Contact count
        
        let tipSwitch = (data[1] & 0x01) != 0
        let contactID = Int((data[1] >> 1) & 0x3F)
        
        let x = Int(data[2]) | (Int(data[3]) << 8)
        let y = Int(data[4]) | (Int(data[5]) << 8)
        let contactCount = data.count > 6 ? Int(data[6]) : 1
        
        // Create touch point
        let rawPoint = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let screenPoint = coordinateMapper.mapToScreen(rawPoint)
        
        let touchPoint = TouchPoint(
            id: contactID,
            x: screenPoint.x,
            y: screenPoint.y,
            isActive: tipSwitch,
            timestamp: Date()
        )
        
        // Update active contacts
        if tipSwitch {
            activeContacts[contactID] = touchPoint
        } else {
            activeContacts.removeValue(forKey: contactID)
        }
        
        // Send to gesture engine
        gestureEngine.processTouches(Array(activeContacts.values))
        
        // Debug output (can be disabled)
        if configuration.debugMode {
            print("Touch: ID=\(contactID) Active=\(tipSwitch) Raw=(\(x),\(y)) Screen=(\(Int(screenPoint.x)),\(Int(screenPoint.y))) Contacts=\(contactCount)")
        }
    }
}
