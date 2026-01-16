//
//  SettingsView.swift
//  TouchRedirectMac
//
//  Settings UI
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var configuration: Configuration
    
    var body: some View {
        Form {
            Section(header: Text("Touch Settings")) {
                Toggle("Enable Touch Redirect", isOn: $configuration.enabled)
                    .onChange(of: configuration.enabled) { _ in
                        configuration.save()
                    }
                
                HStack {
                    Text("Cursor Sensitivity")
                    Slider(value: $configuration.cursorSensitivity, in: 0.1...2.0, step: 0.1)
                    Text(String(format: "%.1f", configuration.cursorSensitivity))
                        .frame(width: 30)
                }
                .onChange(of: configuration.cursorSensitivity) { _ in
                    configuration.save()
                }
                
                HStack {
                    Text("Scroll Sensitivity")
                    Slider(value: $configuration.scrollSensitivity, in: 0.1...3.0, step: 0.1)
                    Text(String(format: "%.1f", configuration.scrollSensitivity))
                        .frame(width: 30)
                }
                .onChange(of: configuration.scrollSensitivity) { _ in
                    configuration.save()
                }
            }
            
            Section(header: Text("Gestures")) {
                Toggle("Two Finger Tap = Right Click", isOn: $configuration.twoFingerTapForRightClick)
                    .onChange(of: configuration.twoFingerTapForRightClick) { _ in
                        configuration.save()
                    }
                
                Toggle("Three Finger Tap = Middle Click", isOn: $configuration.threeFingerTapForMiddleClick)
                    .onChange(of: configuration.threeFingerTapForMiddleClick) { _ in
                        configuration.save()
                    }
            }
            
            Section(header: Text("Display")) {
                HStack {
                    Text("Target Display")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { configuration.targetDisplayID ?? 0 },
                        set: { newValue in
                            configuration.targetDisplayID = newValue == 0 ? nil : newValue
                            configuration.save()
                        }
                    )) {
                        Text("Main Display").tag(UInt32(0))
                        ForEach(NSScreen.screens.indices, id: \.self) { index in
                            let screen = NSScreen.screens[index]
                            if let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                                Text("Display \(index + 1)").tag(displayID)
                            }
                        }
                    }
                }
                
                Button("Reset Calibration") {
                    configuration.resetCalibration()
                }
            }
            
            Section(header: Text("Advanced")) {
                Toggle("Debug Mode", isOn: $configuration.debugMode)
                    .onChange(of: configuration.debugMode) { _ in
                        configuration.save()
                    }
                
                Toggle("Launch at Login", isOn: $configuration.launchAtLogin)
                    .onChange(of: configuration.launchAtLogin) { _ in
                        configuration.save()
                    }
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}
