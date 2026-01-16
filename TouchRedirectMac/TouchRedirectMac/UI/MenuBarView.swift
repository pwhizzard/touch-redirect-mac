//
//  MenuBarView.swift
//  TouchRedirectMac
//
//  Menu bar UI components
//

import SwiftUI

struct MenuBarView: View {
    @ObservedObject var configuration: Configuration
    @State private var isConnected = false
    @State private var statusText = "Searching..."
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: isConnected ? "hand.point.up.left.fill" : "hand.point.up.left")
                    .foregroundColor(isConnected ? .green : .gray)
                Text(statusText)
                    .font(.headline)
            }
            
            Divider()
            
            Toggle("Enable Touch Redirect", isOn: $configuration.enabled)
                .onChange(of: configuration.enabled) { _ in
                    configuration.save()
                }
            
            Divider()
            
            Button("Settings...") {
                // Open settings window
            }
            
            Button("Calibrate Display") {
                // Open calibration window
            }
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 250)
    }
}
