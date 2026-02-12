//
//  CalibrationWindow.swift
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
//  Full-screen calibration UI for mapping touch coordinates to screen positions.
//  Displays targets for users to touch, collecting calibration data points.
//

import Cocoa

// MARK: - Calibration Data

/// Calibration point with screen position and captured touch coordinates
struct CalibrationPoint {
    let screenX: CGFloat
    let screenY: CGFloat
    var touchX: CGFloat?
    var touchY: CGFloat?
    
    var isCalibrated: Bool {
        return touchX != nil && touchY != nil
    }
    
    /// Convert to tuple format for affine computation
    var asTuple: (touch: CGPoint, screen: CGPoint)? {
        guard let tx = touchX, let ty = touchY else { return nil }
        return (touch: CGPoint(x: tx, y: ty), screen: CGPoint(x: screenX, y: screenY))
    }
}

/// Calibration mode
enum CalibrationMode {
    case basic    // 5 points: center + 4 corners
    case advanced // 9 points: 3x3 grid
    
    var pointCount: Int {
        switch self {
        case .basic: return 5
        case .advanced: return 9
        }
    }
}

/// Window that displays calibration targets
class CalibrationWindow: NSWindow {
    private var calibrationView: CalibrationView!
    private var mode: CalibrationMode
    private var points: [CalibrationPoint] = []
    private var currentPointIndex: Int = 0
    private var onComplete: (([CalibrationPoint]) -> Void)?
    private var onCancel: (() -> Void)?
    
    /// Screen manager for consistent screen detection
    private let screenManager = ScreenManager.shared
    
    // Debounce: require finger lift between points
    private var waitingForLift: Bool = false
    private var lastTouchTime: Date = .distantPast
    private let minTimeBetweenPoints: TimeInterval = 0.3
    
    init(mode: CalibrationMode, onComplete: @escaping ([CalibrationPoint]) -> Void, onCancel: @escaping () -> Void) {
        self.mode = mode
        self.onComplete = onComplete
        self.onCancel = onCancel
        
        // Use ScreenManager for consistent screen detection
        screenManager.updateTargetScreen()
        let frame = screenManager.screenFrame
        
        log("Calibration using screen: \(screenManager.screenName)")
        log("  Full frame: \(Int(frame.width))x\(Int(frame.height)) at (\(Int(frame.origin.x)), \(Int(frame.origin.y)))")
        
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        setupCalibrationPoints(screenFrame: frame)
        
        // Create container view for proper layering
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
        containerView.autoresizingMask = [.width, .height]
        
        // Add blur effect background first
        let visualEffect = NSVisualEffectView(frame: containerView.bounds)
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        containerView.addSubview(visualEffect)
        
        // Add calibration view on top
        setupView(screenFrame: frame)
        calibrationView.autoresizingMask = [.width, .height]
        containerView.addSubview(calibrationView)
        
        self.contentView = containerView
        
        log("Calibration window created with \(points.count) points")
    }
    
    private func setupCalibrationPoints(screenFrame: CGRect) {
        // Calculate margins:
        // - Top margin must avoid menubar (typically 24-30px) plus target visibility
        // - Side and bottom margins need target visibility
        // Keep targets as close to edges as possible for best calibration accuracy
        let menubarHeight = screenManager.menubarHeight
        let dockHeight = screenManager.dockHeight
        let targetRadius: CGFloat = 38  // Half of max target size (60 * 1.08 / 2 ≈ 32) + glow buffer
        
        // Minimal margins from screen edges - targets should be close to edges for accuracy
        let topMargin = max(50, menubarHeight + targetRadius + 5)
        let bottomMargin = max(50, dockHeight + targetRadius + 5)
        let sideMargin: CGFloat = 50
        
        let w = screenFrame.width
        let h = screenFrame.height
        
        // Use LOCAL coordinates (relative to this screen, Y-down like touch device)
        // We'll convert to global CG coordinates in the Mapper
        let left = sideMargin
        let right = w - sideMargin
        let top = topMargin           // Low Y = top of screen (Y-down convention)
        let bottom = h - bottomMargin  // High Y = bottom of screen
        let centerX = w / 2
        let centerY = h / 2
        
        log("Calibration point setup:")
        log("  Screen size: \(Int(w))x\(Int(h))")
        log("  Screen origin: (\(Int(screenFrame.origin.x)), \(Int(screenFrame.origin.y)))")
        log("  Menubar: \(Int(menubarHeight))px, Dock: \(Int(dockHeight))px")
        log("  Margins: top=\(Int(topMargin)), bottom=\(Int(bottomMargin)), sides=\(Int(sideMargin))")
        
        switch mode {
        case .basic:
            // 5 points: corners + center
            // Order: TL, TR, Center, BL, BR
            points = [
                CalibrationPoint(screenX: left, screenY: top),       // Top-left
                CalibrationPoint(screenX: right, screenY: top),      // Top-right
                CalibrationPoint(screenX: centerX, screenY: centerY), // Center
                CalibrationPoint(screenX: left, screenY: bottom),    // Bottom-left
                CalibrationPoint(screenX: right, screenY: bottom),   // Bottom-right
            ]
        case .advanced:
            // 9 points: 3x3 grid
            points = [
                CalibrationPoint(screenX: left, screenY: top),       // Top-left
                CalibrationPoint(screenX: centerX, screenY: top),    // Top-center
                CalibrationPoint(screenX: right, screenY: top),      // Top-right
                CalibrationPoint(screenX: left, screenY: centerY),   // Middle-left
                CalibrationPoint(screenX: centerX, screenY: centerY), // Center
                CalibrationPoint(screenX: right, screenY: centerY),  // Middle-right
                CalibrationPoint(screenX: left, screenY: bottom),    // Bottom-left
                CalibrationPoint(screenX: centerX, screenY: bottom), // Bottom-center
                CalibrationPoint(screenX: right, screenY: bottom),   // Bottom-right
            ]
        }
        
        for (i, p) in points.enumerated() {
            log("  Point \(i+1): (\(Int(p.screenX)), \(Int(p.screenY))) [local, Y-down]")
        }
    }
    
    private func setupView(screenFrame: CGRect) {
        let viewFrame = NSRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height)
        calibrationView = CalibrationView(frame: viewFrame, screenHeight: screenFrame.height)
        // Note: contentView is set in init after layering with blur
        
        updateView()
    }
    
    private func updateView() {
        calibrationView.setPoints(points, currentIndex: currentPointIndex)
        calibrationView.setInstructions("Touch the highlighted target")
    }
    
    func handleTouch(rawX: CGFloat, rawY: CGFloat, isTouching: Bool) {
        guard currentPointIndex < points.count else { return }
        
        if !isTouching {
            if waitingForLift {
                waitingForLift = false
                updateView()
            }
            return
        }
        
        if waitingForLift { return }
        
        let now = Date()
        if now.timeIntervalSince(lastTouchTime) < minTimeBetweenPoints { return }
        
        // Record touch coordinates
        points[currentPointIndex].touchX = rawX
        points[currentPointIndex].touchY = rawY
        lastTouchTime = now
        
        log("Calibration point \(currentPointIndex + 1): screen=(\(Int(points[currentPointIndex].screenX)), \(Int(points[currentPointIndex].screenY))) touch=(\(Int(rawX)), \(Int(rawY)))")
        
        currentPointIndex += 1
        waitingForLift = true
        
        if currentPointIndex >= points.count {
            log("Calibration complete!")
            
            // Show the last point as completed before closing
            calibrationView.setPoints(points, currentIndex: points.count) // No active point
            calibrationView.setInstructions("Calibration complete!")
            
            let capturedPoints = self.points
            let completion = self.onComplete
            
            // Give user time to see the last point turn green
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                completion?(capturedPoints)
                self?.orderOut(nil)
                self?.onComplete = nil
                self?.onCancel = nil
            }
        } else {
            calibrationView.setPoints(points, currentIndex: currentPointIndex)
            calibrationView.setInstructions("Point captured! Lift finger, then touch point \(currentPointIndex + 1)")
        }
    }
    
    /// Callback to switch to a different screen
    var onSwitchScreen: (() -> Void)?
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            let cancelHandler = onCancel
            onCancel = nil
            onComplete = nil
            cancelHandler?()
        } else if event.keyCode == 48 { // Tab
            // Switch to next available screen
            log("Tab pressed - switching to next screen")
            onSwitchScreen?()
        }
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// View that draws calibration targets
class CalibrationView: NSView {
    private var points: [CalibrationPoint] = []
    private var currentIndex: Int = 0
    private var instructions: String = ""
    private var screenHeight: CGFloat = 1080
    private var pulsePhase: CGFloat = 0
    private var pulseTimer: Timer?
    
    init(frame: NSRect, screenHeight: CGFloat) {
        self.screenHeight = screenHeight
        super.init(frame: frame)
        startPulseAnimation()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    deinit {
        pulseTimer?.invalidate()
    }
    
    private func startPulseAnimation() {
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.pulsePhase += 0.1
            if self.pulsePhase > CGFloat.pi * 2 {
                self.pulsePhase = 0
            }
            self.needsDisplay = true
        }
    }
    
    func setPoints(_ points: [CalibrationPoint], currentIndex: Int) {
        self.points = points
        self.currentIndex = currentIndex
        needsDisplay = true
    }
    
    func setInstructions(_ text: String) {
        self.instructions = text
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        // Layout constants - generous spacing for clean design
        let topPadding: CGFloat = 60  // Distance from top of screen (accounts for menu bar)
        let elementSpacing: CGFloat = 16  // Breathing room between elements
        
        let completedCount = points.filter { $0.isCalibrated }.count
        let totalCount = points.count
        
        // === TOP SECTION: Progress counter + bar + instructions ===
        
        // 1. Progress counter (e.g., "1 of 5") - subtle, secondary
        let progressText = "\(completedCount) of \(totalCount)"
        let progressAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.5),
            .paragraphStyle: paragraphStyle
        ]
        let progressY = bounds.height - topPadding
        let progressRect = NSRect(x: 0, y: progressY, width: bounds.width, height: 20)
        progressText.draw(in: progressRect, withAttributes: progressAttrs)
        
        // 2. Progress bar - thin, elegant
        let barWidth: CGFloat = 160
        let barHeight: CGFloat = 3
        let barX = (bounds.width - barWidth) / 2
        let barY = progressY - elementSpacing - barHeight
        
        // Background track
        NSColor.white.withAlphaComponent(0.15).setFill()
        let bgPath = NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: barWidth, height: barHeight), xRadius: 1.5, yRadius: 1.5)
        bgPath.fill()
        
        // Progress fill
        let progress = CGFloat(completedCount) / CGFloat(max(1, totalCount))
        if progress > 0 {
            NSColor.systemGreen.setFill()
            let progressPath = NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: barWidth * progress, height: barHeight), xRadius: 1.5, yRadius: 1.5)
            progressPath.fill()
        }
        
        // 3. Instructions - primary text, prominent
        let instructionY = barY - elementSpacing - 36
        let instructionAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let textRect = NSRect(x: 0, y: instructionY, width: bounds.width, height: 36)
        instructions.draw(in: textRect, withAttributes: instructionAttrs)
        
        // === CALIBRATION TARGETS ===
        for (index, point) in points.enumerated() {
            let isActive = index == currentIndex
            let isCompleted = point.isCalibrated
            
            // Points are stored in LOCAL coords with Y-down convention
            // AppKit uses Y-up, so flip Y for drawing
            let drawX = point.screenX
            let drawY = screenHeight - point.screenY
            
            drawTarget(
                at: NSPoint(x: drawX, y: drawY),
                isActive: isActive,
                isCompleted: isCompleted,
                number: index + 1
            )
        }
        
        // === BOTTOM HINT ===
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.4),
            .paragraphStyle: paragraphStyle
        ]
        let hintRect = NSRect(x: 0, y: 40, width: bounds.width, height: 24)
        "Touch the center of each target  •  Tab to switch screen  •  ESC to cancel".draw(in: hintRect, withAttributes: hintAttrs)
    }
    
    private func drawTarget(at point: NSPoint, isActive: Bool, isCompleted: Bool, number: Int) {
        // Pulse animation for active target - keep modest to avoid edge clipping
        let pulseScale: CGFloat = isActive ? 1.0 + 0.08 * sin(pulsePhase) : 1.0
        let baseSize: CGFloat = isActive ? 60 : 44
        let size = baseSize * pulseScale
        let rect = NSRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size)
        
        let outerColor: NSColor
        if isCompleted {
            outerColor = .systemGreen
        } else if isActive {
            // Pulsing alpha for active target
            let pulseAlpha = 0.7 + 0.3 * sin(pulsePhase)
            outerColor = NSColor.systemRed.withAlphaComponent(pulseAlpha)
        } else {
            outerColor = NSColor.white.withAlphaComponent(0.4)
        }
        
        // Glow effect for active target
        if isActive {
            let glowSize = size + 16
            let glowRect = NSRect(x: point.x - glowSize/2, y: point.y - glowSize/2, width: glowSize, height: glowSize)
            NSColor.systemRed.withAlphaComponent(0.15 + 0.1 * sin(pulsePhase)).setFill()
            NSBezierPath(ovalIn: glowRect).fill()
        }
        
        // Outer circle
        outerColor.setStroke()
        let outerPath = NSBezierPath(ovalIn: rect)
        outerPath.lineWidth = isActive ? 3 : 2
        outerPath.stroke()
        
        // Inner circle
        let innerSize: CGFloat = size * 0.4
        let innerRect = NSRect(x: point.x - innerSize/2, y: point.y - innerSize/2, width: innerSize, height: innerSize)
        let innerPath = NSBezierPath(ovalIn: innerRect)
        innerPath.lineWidth = 2
        innerPath.stroke()
        
        // Center dot
        let dotSize: CGFloat = isActive ? 10 : 6
        let dotRect = NSRect(x: point.x - dotSize/2, y: point.y - dotSize/2, width: dotSize, height: dotSize)
        outerColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        
        // Crosshairs for active point
        if isActive {
            let crossSize: CGFloat = size + 40
            NSColor.systemRed.withAlphaComponent(0.4).setStroke()
            
            let vPath = NSBezierPath()
            vPath.move(to: NSPoint(x: point.x, y: point.y - crossSize/2))
            vPath.line(to: NSPoint(x: point.x, y: point.y + crossSize/2))
            vPath.lineWidth = 2
            vPath.stroke()
            
            let hPath = NSBezierPath()
            hPath.move(to: NSPoint(x: point.x - crossSize/2, y: point.y))
            hPath.line(to: NSPoint(x: point.x + crossSize/2, y: point.y))
            hPath.lineWidth = 2
            hPath.stroke()
        }
        
        // Number label
        let numStr = "\(number)"
        let numAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: outerColor
        ]
        let numSize = numStr.size(withAttributes: numAttributes)
        let numPoint = NSPoint(x: point.x - numSize.width/2, y: point.y - size/2 - numSize.height - 8)
        numStr.draw(at: numPoint, withAttributes: numAttributes)
    }
}
