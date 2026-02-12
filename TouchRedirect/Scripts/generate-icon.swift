#!/usr/bin/env swift
// Script to generate TouchRedirect app icons
// Run with: swift Scripts/generate-icon.swift

import Cocoa

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDir = "Sources/TouchRedirect/Resources/Assets.xcassets/AppIcon.appiconset"

// Ensure output directory exists
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for size in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    
    image.lockFocus()
    
    // Background gradient - deep blue to purple
    let gradient = NSGradient(colors: [
        NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0),
        NSColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 1.0)
    ])!
    
    // Draw rounded rect background
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = CGFloat(size) * 0.22 // macOS icon corner radius
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    gradient.draw(in: path, angle: -45)
    
    // Draw a stylized hand/touch icon using SF Symbols
    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.5, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "hand.point.up.left.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        
        let symbolSize = symbol.size
        let x = (CGFloat(size) - symbolSize.width) / 2
        let y = (CGFloat(size) - symbolSize.height) / 2 - CGFloat(size) * 0.05
        
        // Draw white symbol
        NSColor.white.setFill()
        symbol.draw(at: NSPoint(x: x, y: y), from: .zero, operation: .sourceOver, fraction: 1.0)
    }
    
    image.unlockFocus()
    
    // Save as PNG
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for size \(size)")
        continue
    }
    
    let filename = "\(outputDir)/icon_\(size).png"
    try? pngData.write(to: URL(fileURLWithPath: filename))
    print("Generated: \(filename)")
}

print("Done! Icon files generated in \(outputDir)")
