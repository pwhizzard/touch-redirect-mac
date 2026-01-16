//
//  CalibrationView.swift
//  TouchRedirectMac
//
//  Display calibration UI
//

import SwiftUI

struct CalibrationView: View {
    @ObservedObject var configuration: Configuration
    @State private var calibrationStep = 0
    @State private var instructions = "Touch the center of the screen to calibrate"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Display Calibration")
                .font(.title)
            
            Text(instructions)
                .multilineTextAlignment(.center)
                .padding()
            
            Spacer()
            
            if configuration.calibration != nil {
                VStack(spacing: 10) {
                    Text("Current Calibration:")
                        .font(.headline)
                    
                    if let cal = configuration.calibration {
                        Text("Offset: (\(String(format: "%.3f", cal.offsetX)), \(String(format: "%.3f", cal.offsetY)))")
                        Text("Scale: (\(String(format: "%.3f", cal.scaleX)), \(String(format: "%.3f", cal.scaleY)))")
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
            
            HStack(spacing: 20) {
                Button("Reset Calibration") {
                    configuration.resetCalibration()
                    instructions = "Calibration reset. Touch the screen to recalibrate."
                    calibrationStep = 0
                }
                
                Button("Close") {
                    NSApplication.shared.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .padding()
        .frame(width: 600, height: 400)
    }
}
