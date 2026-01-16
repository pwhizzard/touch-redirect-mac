//
//  main.swift
//  TouchRedirectMac
//
//  Pure AppKit entry point - matches working test pattern
//

import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // This is key for menu bar apps!
let delegate = AppDelegate()
app.delegate = delegate
app.run()
