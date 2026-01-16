//
//  TouchPoint.swift
//  TouchRedirectMac
//
//  Model representing a touch point
//

import Foundation
import CoreGraphics

struct TouchPoint {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let isActive: Bool
    let timestamp: Date
    
    var position: CGPoint {
        return CGPoint(x: x, y: y)
    }
}
