//
//  Mapper.swift
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
//  Transforms raw touch coordinates to screen coordinates using affine calibration.
//  Handles coordinate system conversion between touch device, NSScreen, and CGEvent.
//

import Foundation
import CoreGraphics
import Cocoa

// MARK: - Affine Transform

/// Affine transformation matrix for touch-to-screen mapping
/// Transforms (touchX, touchY) -> (screenX, screenY) using:
/// screenX = a * touchX + b * touchY + tx
/// screenY = c * touchX + d * touchY + ty
struct AffineTransform2D {
    var a: CGFloat = 1.0   // X scale
    var b: CGFloat = 0.0   // X shear
    var c: CGFloat = 0.0   // Y shear
    var d: CGFloat = 1.0   // Y scale
    var tx: CGFloat = 0.0  // X translation
    var ty: CGFloat = 0.0  // Y translation
    
    /// Identity transform (no change)
    static let identity = AffineTransform2D()
    
    /// Apply transform to a point
    func apply(x: CGFloat, y: CGFloat) -> CGPoint {
        let newX = a * x + b * y + tx
        let newY = c * x + d * y + ty
        return CGPoint(x: newX, y: newY)
    }
    
    /// Compute affine transform from calibration points
    /// Uses simple linear regression for X and Y independently (ignoring cross-terms)
    /// This is more robust than full affine when touch axes are aligned with screen axes
    static func fromCalibrationPoints(_ points: [(touch: CGPoint, screen: CGPoint)]) -> AffineTransform2D? {
        guard points.count >= 3 else {
            log("Need at least 3 points for affine transform")
            return nil
        }
        
        // Simple approach: compute scale and offset for X and Y independently
        // screenX = a * touchX + tx
        // screenY = d * touchY + ty
        // (ignore b and c cross-terms since touch axes align with screen axes)
        
        let n = CGFloat(points.count)
        
        var sumTX: CGFloat = 0, sumTY: CGFloat = 0
        var sumSX: CGFloat = 0, sumSY: CGFloat = 0
        var sumTX2: CGFloat = 0, sumTY2: CGFloat = 0
        var sumTXSX: CGFloat = 0, sumTYSY: CGFloat = 0
        
        for point in points {
            sumTX += point.touch.x
            sumTY += point.touch.y
            sumSX += point.screen.x
            sumSY += point.screen.y
            sumTX2 += point.touch.x * point.touch.x
            sumTY2 += point.touch.y * point.touch.y
            sumTXSX += point.touch.x * point.screen.x
            sumTYSY += point.touch.y * point.screen.y
        }
        
        // Linear regression for X: screenX = a * touchX + tx
        let denomX = n * sumTX2 - sumTX * sumTX
        guard abs(denomX) > 1e-10 else {
            logError("Cannot compute X scale - insufficient variation")
            return nil
        }
        let a = (n * sumTXSX - sumTX * sumSX) / denomX
        let tx = (sumSX - a * sumTX) / n
        
        // Linear regression for Y: screenY = d * touchY + ty
        let denomY = n * sumTY2 - sumTY * sumTY
        guard abs(denomY) > 1e-10 else {
            logError("Cannot compute Y scale - insufficient variation")
            return nil
        }
        let d = (n * sumTYSY - sumTY * sumSY) / denomY
        let ty = (sumSY - d * sumTY) / n
        
        log("Computed transform: scaleX=\(String(format: "%.6f", a)), scaleY=\(String(format: "%.6f", d))")
        log("  offsetX=\(String(format: "%.2f", tx)), offsetY=\(String(format: "%.2f", ty))")
        
        // No margin adjustment - we'll use non-linear edge correction instead
        return AffineTransform2D(
            a: a,
            b: 0,
            c: 0,
            d: d,
            tx: tx,
            ty: ty
        )
    }
}

/// Maps touch coordinates from a touch device to screen coordinates.
/// Supports per-device mapping state when used with device profiles.
class Mapper {
    /// Current affine transform for mapping
    private var transform: AffineTransform2D = .identity

    /// Edge boost strength (0 = none, 0.3 = strong)
    /// Compensates for devices that reserve edge zones for their own gestures
    var edgeBoostStrength: CGFloat = 0.15 {
        didSet {
            log("Edge boost strength set to \(String(format: "%.2f", edgeBoostStrength))")
        }
    }

    /// How far from edge (as fraction of screen) the boost starts
    private let edgeBoostZone: CGFloat = 0.15

    /// Fallback linear mapping (used if no calibration)
    private var touchMinX: CGFloat = 88.0
    private var touchMaxX: CGFloat = 15859.0
    private var touchMinY: CGFloat = 86.0
    private var touchMaxY: CGFloat = 9525.0

    /// Whether we have a valid affine calibration
    private(set) var hasAffineCalibration: Bool = false

    /// Screen manager reference
    private let screenManager = ScreenManager.shared

    /// Configuration
    var invertY: Bool = false

    /// Debug: track min/max seen values
    private var seenMinX: CGFloat = 99999
    private var seenMaxX: CGFloat = 0
    private var seenMinY: CGFloat = 99999
    private var seenMaxY: CGFloat = 0
    private var calibrationLogCount = 0

    /// Callback when calibration becomes invalid due to screen change
    var onCalibrationInvalidated: (() -> Void)?

    /// The device profile this mapper is configured for (nil = legacy global mapper)
    private(set) var deviceProfile: TouchDeviceProfile?

    /// The device identity key used for per-device persistence (nil = use global config)
    private(set) var devicePersistenceKey: String?

    /// Notification observer token for screen changes
    private var screenChangeObserver: NSObjectProtocol?

    /// Notification observer for display binding changes
    private var bindingChangeObserver: NSObjectProtocol?

    /// Cached per-device display frame (nil = use global screenManager.screenFrame)
    private var resolvedDisplayFrame: CGRect?
    private var resolvedDisplayID: CGDirectDisplayID = 0

    // MARK: - Initialization

    /// Default initializer (global / legacy mapper)
    init() {
        log("Mapper initialized (global)")
        log("Screen: \(screenManager.screenName), \(Int(screenManager.screenFrame.width))x\(Int(screenManager.screenFrame.height))")

        // Load edge boost from config
        edgeBoostStrength = CGFloat(Config.shared.edgeBoostStrength)

        // Listen for screen changes via NotificationCenter (supports multiple observers)
        observeScreenChanges()
    }

    /// Profile-aware initializer for per-device mapping
    init(profile: TouchDeviceProfile, deviceIdentity: TouchDeviceIdentity) {
        self.deviceProfile = profile
        self.devicePersistenceKey = deviceIdentity.persistenceKey

        // Set defaults from profile
        touchMinX = profile.defaultMinX
        touchMaxX = profile.defaultMaxX
        touchMinY = profile.defaultMinY
        touchMaxY = profile.defaultMaxY
        edgeBoostStrength = profile.defaultEdgeCompensation ? 0.15 : 0.0

        log("Mapper initialized for \(profile.displayName) (\(deviceIdentity))")

        // Load per-device overrides from config
        let key = deviceIdentity.persistenceKey
        edgeBoostStrength = CGFloat(Config.shared.edgeBoostStrength(forDevice: key))

        if let transform = Config.shared.affineTransform(forDevice: key) {
            loadTransformValues(transform)
        }

        // Resolve per-device display target
        refreshResolvedDisplay()

        log("Screen: \(screenManager.screenName), \(Int(targetFrame.width))x\(Int(targetFrame.height))")

        // Listen for screen changes via NotificationCenter (supports multiple observers)
        observeScreenChanges()

        // Listen for binding changes from Settings UI
        bindingChangeObserver = NotificationCenter.default.addObserver(
            forName: .deviceDisplayBindingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshResolvedDisplay()
        }
    }

    /// Subscribe to screen change notifications so all Mapper instances are notified
    private func observeScreenChanges() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: .screenConfigurationDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let changeInfo = notification.userInfo?["changeInfo"] as? ScreenChangeInfo {
                self?.handleScreenChange(changeInfo)
            }
        }
    }

    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = bindingChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// The effective screen frame for this mapper (per-device resolved or global fallback)
    var targetFrame: CGRect {
        return resolvedDisplayFrame ?? screenManager.screenFrame
    }

    /// Re-resolve the display target for this device from config + auto-correlation
    private func refreshResolvedDisplay() {
        guard let profile = deviceProfile, let key = devicePersistenceKey else {
            resolvedDisplayFrame = nil
            return
        }
        let result = screenManager.resolveDisplay(forDeviceKey: key, profile: profile)
        resolvedDisplayFrame = result.screen.frame
        resolvedDisplayID = result.displayID
        log("Mapper[\(profile.displayName)]: resolved display → \(result.screen.localizedName) (\(result.displayID))")
    }
    
    /// Handle screen configuration changes
    private func handleScreenChange(_ changeInfo: ScreenChangeInfo) {
        log("Mapper handling screen change...")

        // Re-resolve per-device display target (screens may have appeared/disappeared)
        refreshResolvedDisplay()

        if changeInfo.requiresRecalibration && hasAffineCalibration {
            log("Screen change requires recalibration!")
            onCalibrationInvalidated?()
        }
        
        // Reset seen ranges for new screen
        seenMinX = 99999
        seenMaxX = 0
        seenMinY = 99999
        seenMaxY = 0
        calibrationLogCount = 0
    }
    
    /// Set affine transform from calibration
    func setAffineTransform(_ transform: AffineTransform2D) {
        self.transform = transform
        self.hasAffineCalibration = true
        log("Affine transform set:")
        log("  a=\(String(format: "%.6f", transform.a)), b=\(String(format: "%.6f", transform.b)), tx=\(String(format: "%.2f", transform.tx))")
        log("  c=\(String(format: "%.6f", transform.c)), d=\(String(format: "%.6f", transform.d)), ty=\(String(format: "%.2f", transform.ty))")
    }
    
    /// Set linear mapping fallback (for compatibility)
    func setTouchRange(minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        touchMinX = minX
        touchMaxX = maxX
        touchMinY = minY
        touchMaxY = maxY
        hasAffineCalibration = false
        log("Linear touch range set: X=\(Int(minX))-\(Int(maxX)), Y=\(Int(minY))-\(Int(maxY))")
    }
    
    /// Map touch coordinates to screen coordinates
    func mapToScreen(touchX: UInt16, touchY: UInt16) -> CGPoint {
        let rawX = CGFloat(touchX)
        var rawY = CGFloat(touchY)
        
        // Track min/max for debugging
        seenMinX = min(seenMinX, rawX)
        seenMaxX = max(seenMaxX, rawX)
        seenMinY = min(seenMinY, rawY)
        seenMaxY = max(seenMaxY, rawY)
        
        calibrationLogCount += 1
        if calibrationLogCount % 100 == 0 {
            log("Touch range seen: X=\(Int(seenMinX))-\(Int(seenMaxX)), Y=\(Int(seenMinY))-\(Int(seenMaxY))")
        }
        
        // Apply Y inversion if configured (before mapping)
        if invertY {
            // Invert around the midpoint of the observed range
            let midY = (touchMinY + touchMaxY) / 2
            rawY = 2 * midY - rawY
        }
        
        var screenPoint: CGPoint
        let frame = targetFrame

        // Primary display height for Cocoa→CGEvent (Quartz) Y-axis conversion.
        // CGEvent origin is at the TOP-LEFT of the primary display; Y increases downward.
        // Cocoa (NSScreen) origin is BOTTOM-LEFT of the primary display; Y increases upward.
        // The correct conversion is:  quartzY = primaryHeight - cocoaY
        //
        // IMPORTANT: NSScreen.screens.first is NOT guaranteed to be the primary display.
        // CGMainDisplayID() always returns the primary (menu-bar) display, so we use its
        // Quartz bounds to get a deterministic, correct height for the Y flip.
        let primaryHeight = CGFloat(CGDisplayBounds(CGMainDisplayID()).height)

        var localX: CGFloat
        var localY: CGFloat

        if hasAffineCalibration {
            // Use affine transform - produces LOCAL coordinates (Y-down convention)
            let localPoint = transform.apply(x: rawX, y: rawY)
            localX = localPoint.x
            localY = localPoint.y
        } else {
            // Fallback to linear mapping - also produces LOCAL coordinates
            let rangeX = touchMaxX - touchMinX
            let rangeY = touchMaxY - touchMinY

            guard rangeX > 100 && rangeY > 100 else {
                // Return center of target screen in CGEvent coords
                let centerNSY = frame.origin.y + frame.height / 2
                return CGPoint(x: frame.midX, y: primaryHeight - centerNSY)
            }

            let normalizedX = (rawX - touchMinX) / rangeX
            let normalizedY = (rawY - touchMinY) / rangeY

            // Local coordinates (Y-down)
            localX = normalizedX * frame.width
            localY = normalizedY * frame.height
        }

        // Apply edge boost ONLY to right edge (X axis only)
        // Some devices reserve the right edge for their own gestures, so we stretch toward it
        let normX = localX / frame.width
        let boostedNormX = rightEdgeBoostFunction(normX)
        localX = boostedNormX * frame.width
        // Note: Y axis has no edge boost - only right edge needs compensation

        // Clamp local coords to screen dimensions
        localX = max(0, min(frame.width - 1, localX))
        localY = max(0, min(frame.height - 1, localY))

        // Convert LOCAL (Y-down) to CGEvent coordinates
        // Step 1: Local to NSScreen (Cocoa Y-up)
        let nsScreenX = frame.origin.x + localX
        let nsScreenY = frame.origin.y + frame.height - localY

        // Step 2: NSScreen (Cocoa) to CGEvent (Quartz): flip Y around primary display
        screenPoint = CGPoint(
            x: nsScreenX,
            y: primaryHeight - nsScreenY
        )

        // One-time log to verify extended-display coordinate math
        if calibrationLogCount == 1 {
            log("mapToScreen: target frame=\(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))x\(Int(frame.height))")
            log("  primaryHeight=\(Int(primaryHeight)) local=(\(Int(localX)),\(Int(localY))) → CGEvent=(\(Int(screenPoint.x)),\(Int(screenPoint.y)))")
        }

        return screenPoint
    }
    
    /// Right edge boost function: ONLY stretches values near the right edge (t near 1)
    /// Some devices reserve their right edge for system gestures, making it hard to reach
    /// This compensates by gently stretching touch input toward the right edge
    private func rightEdgeBoostFunction(_ t: CGFloat) -> CGFloat {
        // No boost if strength is 0
        guard edgeBoostStrength > 0 else { return t }
        
        // Only apply boost near the RIGHT edge (t > 1 - edgeBoostZone)
        // Left edge (t near 0) gets NO boost
        if t > (1 - edgeBoostZone) {
            // Near right edge - stretch toward 1
            let distFromEdge = (1 - t) / edgeBoostZone  // 0 at edge, 1 at zone boundary
            let boost = (1 - distFromEdge) * edgeBoostStrength * edgeBoostZone
            return min(1, t + boost)
        } else {
            // Center and left regions - no boost
            return t
        }
    }
    
    /// Reset to default calibration (using profile defaults if available)
    func resetCalibration() {
        transform = .identity
        hasAffineCalibration = false

        if let profile = deviceProfile {
            touchMinX = profile.defaultMinX
            touchMaxX = profile.defaultMaxX
            touchMinY = profile.defaultMinY
            touchMaxY = profile.defaultMaxY
            edgeBoostStrength = profile.defaultEdgeCompensation ? 0.15 : 0.0
        } else {
            // Legacy Desk Pro defaults
            touchMinX = 88.0
            touchMaxX = 15859.0
            touchMinY = 86.0
            touchMaxY = 9525.0
        }

        // Clear per-device persisted calibration
        if let key = devicePersistenceKey {
            Config.shared.resetCalibration(forDevice: key)
        }

        log("Calibration reset to defaults\(deviceProfile.map { " for \($0.displayName)" } ?? "")")
    }
    
    /// Get current transform for persistence
    func getTransformValues() -> [String: Double] {
        return [
            "a": Double(transform.a),
            "b": Double(transform.b),
            "c": Double(transform.c),
            "d": Double(transform.d),
            "tx": Double(transform.tx),
            "ty": Double(transform.ty)
        ]
    }
    
    /// Load transform from persisted values
    func loadTransformValues(_ values: [String: Double]) {
        guard let a = values["a"], let b = values["b"],
              let c = values["c"], let d = values["d"],
              let tx = values["tx"], let ty = values["ty"] else {
            log("Invalid transform values, using defaults")
            return
        }
        
        transform = AffineTransform2D(
            a: CGFloat(a), b: CGFloat(b),
            c: CGFloat(c), d: CGFloat(d),
            tx: CGFloat(tx), ty: CGFloat(ty)
        )
        hasAffineCalibration = true
        log("Loaded affine transform from config")
    }
}
