//
//  HIDDeviceManager.swift
//  TouchRedirectMac
//
//  Manages HID device detection and connection
//

import Foundation
import IOKit.hid
import AppKit

class HIDDeviceManager {
    private var hidManager: IOHIDManager?
    private var device: IOHIDDevice?
    private var parser: TouchReportParser?
    private let configuration: Configuration
    private let eventInjector: EventInjector
    private var isEnabled: Bool = true
    
    // Store the report buffer to prevent deallocation
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    
    // Store a strong reference to self for callbacks
    private var retainedSelf: Unmanaged<HIDDeviceManager>?
    
    init(configuration: Configuration, eventInjector: EventInjector) {
        self.configuration = configuration
        self.eventInjector = eventInjector
        self.parser = TouchReportParser(configuration: configuration, eventInjector: eventInjector)
    }
    
    func startMonitoring() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard let manager = hidManager else {
            print("Failed to create HID manager")
            return
        }
        
        // Set matching criteria for Cisco WebEx Desk Pro Digitizer
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: HIDConstants.vendorID,
            kIOHIDProductIDKey: HIDConstants.productID,
            kIOHIDDeviceUsagePageKey: HIDConstants.usagePageDigitizer
        ]
        
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        
        // Retain self for the duration of monitoring
        retainedSelf = Unmanaged.passRetained(self)
        let context = retainedSelf!.toOpaque()
        
        // Register callbacks using global functions to avoid closure capture issues
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceMatchingCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, hidDeviceRemovalCallback, context)
        
        // Open the manager
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            print("Failed to open HID manager: \(openResult)")
            return
        }
        
        // Schedule with run loop
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue as CFString)
        
        print("HID manager started, waiting for WebEx Desk Pro...")
        notifyAppDelegate("Searching...", connected: false)
    }
    
    func deviceConnected(_ hidDevice: IOHIDDevice) {
        print("Device connected!")
        
        if let product = IOHIDDeviceGetProperty(hidDevice, kIOHIDProductKey as CFString) as? String {
            print("  Product: \(product)")
        }
        
        if let manufacturer = IOHIDDeviceGetProperty(hidDevice, kIOHIDManufacturerKey as CFString) as? String {
            print("  Manufacturer: \(manufacturer)")
        }
        
        // Close existing device if any
        if let existingDevice = device {
            IOHIDDeviceClose(existingDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        
        // Deallocate old report buffer if any
        reportBuffer?.deallocate()
        reportBuffer = nil
        
        // Try to open with exclusive access
        var openResult = IOHIDDeviceOpen(hidDevice, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        
        if openResult == kIOReturnExclusiveAccess {
            print("Device is in use by another process, retrying without seize...")
            openResult = IOHIDDeviceOpen(hidDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        
        if openResult != kIOReturnSuccess {
            print("Failed to open device: \(openResult)")
            notifyAppDelegate("Found but cannot open (Error: \(openResult))", connected: false)
            return
        }
        
        device = hidDevice
        
        // Allocate and store report buffer
        reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        reportBuffer?.initialize(repeating: 0, count: 64)
        
        // Use the same retained context
        let context = retainedSelf!.toOpaque()
        
        // Register for input reports
        IOHIDDeviceRegisterInputReportCallback(hidDevice, reportBuffer!, 64, hidInputReportCallback, context)
        
        print("Device opened successfully!")
        notifyAppDelegate("Connected", connected: true)
    }
    
    func deviceDisconnected(_ hidDevice: IOHIDDevice) {
        print("Device disconnected")
        
        if let existingDevice = device {
            IOHIDDeviceClose(existingDevice, IOOptionBits(kIOHIDOptionsTypeNone))
            device = nil
        }
        
        notifyAppDelegate("Disconnected", connected: false)
    }
    
    func handleInputReport(type: IOHIDReportType, reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        guard isEnabled && configuration.enabled else { return }
        
        // Convert report to Data
        let data = Data(bytes: report, count: length)
        
        // Parse the touch report
        parser?.parseReport(reportID: UInt8(reportID), data: data)
    }
    
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        print("Touch redirect \(enabled ? "enabled" : "disabled")")
    }
    
    private func notifyAppDelegate(_ status: String, connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard self != nil else { return }
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                appDelegate.updateStatus(status, connected: connected)
            }
        }
    }
    
    func stopMonitoring() {
        if let device = device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            self.device = nil
        }
        
        if let manager = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue as CFString)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }
        
        reportBuffer?.deallocate()
        reportBuffer = nil
        
        // Release the retained self
        retainedSelf?.release()
        retainedSelf = nil
    }
    
    deinit {
        stopMonitoring()
    }
}

// Global callback functions to avoid closure capture issues
private func hidDeviceMatchingCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context = context else { return }
    let manager = Unmanaged<HIDDeviceManager>.fromOpaque(context).takeUnretainedValue()
    manager.deviceConnected(device)
}

private func hidDeviceRemovalCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context = context else { return }
    let manager = Unmanaged<HIDDeviceManager>.fromOpaque(context).takeUnretainedValue()
    manager.deviceDisconnected(device)
}

private func hidInputReportCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, type: IOHIDReportType, reportID: UInt32, report: UnsafeMutablePointer<UInt8>, reportLength: CFIndex) {
    guard let context = context else { return }
    let manager = Unmanaged<HIDDeviceManager>.fromOpaque(context).takeUnretainedValue()
    manager.handleInputReport(type: type, reportID: reportID, report: report, length: reportLength)
}
