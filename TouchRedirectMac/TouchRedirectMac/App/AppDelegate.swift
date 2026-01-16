//
//  AppDelegate.swift
//  TouchRedirectMac
//
//  MINIMAL VERSION - Menu bar icon only for testing
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar item - using pattern from working test
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "TR"
        
        // Create a simple menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Touch Redirect", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let statusMenuItem = NSMenuItem(title: "Status: Minimal Test", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.statusItem?.menu = menu
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
    
    // Stub for HIDDeviceManager - will be fully implemented later
    func updateStatus(_ status: String, connected: Bool) {
        if let menu = statusItem?.menu,
           let item = menu.item(withTag: 100) {
            item.title = "Status: \(status)"
        }
        if let button = statusItem?.button {
            button.title = connected ? "👆✓" : "👆"
        }
    }
}
