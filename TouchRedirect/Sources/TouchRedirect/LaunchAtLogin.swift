//
//  LaunchAtLogin.swift
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
//  Manages auto-launch at login using SMAppService (macOS 13+).
//

import Foundation
import ServiceManagement

// MARK: - Launch at Login

/// Manages auto-launch at login functionality
/// Uses SMAppService for macOS 13+ 
class LaunchAtLogin {
    static let shared = LaunchAtLogin()
    
    private init() {}
    
    /// Whether the app is set to launch at login
    var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                // Legacy: Just return the config value
                return Config.shared.launchAtLogin
            }
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                        log("Launch at login: enabled")
                    } else {
                        try SMAppService.mainApp.unregister()
                        log("Launch at login: disabled")
                    }
                } catch {
                    logError("Failed to \(newValue ? "enable" : "disable") launch at login: \(error)")
                }
            } else {
                // Legacy macOS - just store the preference
                // The user will need to add the app manually to Login Items
                log("Launch at login requires macOS 13+. Please add the app manually to Login Items.")
            }
            
            Config.shared.launchAtLogin = newValue
        }
    }
    
    /// Check and sync the current status
    func checkStatus() {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            let statusString: String
            switch status {
            case .notRegistered:
                statusString = "not registered"
            case .enabled:
                statusString = "enabled"
            case .requiresApproval:
                statusString = "requires approval"
            case .notFound:
                statusString = "not found"
            @unknown default:
                statusString = "unknown"
            }
            log("Launch at login status: \(statusString)")
            
            // Sync config with actual status
            Config.shared.launchAtLogin = (status == .enabled)
        }
    }
}
