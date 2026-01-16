# Building Touch Redirect

This guide explains how to build and run Touch Redirect from source.

## Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 15 or later (includes Swift 5.9+)
- A Cisco WebEx Desk Pro connected via USB-C (for runtime testing)

## Supported Devices

Touch Redirect is currently designed **specifically for the Cisco WebEx Desk Pro**.
It communicates via USB HID with hardcoded identifiers:

| Property     | Value                     |
|--------------|---------------------------|
| Vendor ID    | `0x05a6` (Cisco Systems)  |
| Product ID   | `0x0b05` (Desk Pro)       |
| HID Usage    | Digitizer / Touch Screen  |

### Why isn't it generic?

Different touch devices use different HID report formats. The Desk Pro sends
56-byte reports with a specific bit layout for multi-touch data. Other devices
may use entirely different structures, coordinate ranges, and report IDs.

### Adding Support for Other Touchscreens

To add support for a different USB touchscreen:

1. **Identify the device** – Use a tool like [USB Prober](https://developer.apple.com/download/more/?=Additional%20Tools) or `ioreg` to find the Vendor ID, Product ID, and HID usage page.

2. **Update `HIDManager.swift`** – Add the new IDs to the device matching criteria (or make matching more flexible).

3. **Capture HID reports** – Enable diagnostic logging to capture raw byte data from the device.

4. **Update `TouchParser.swift`** – Decode the device's specific report format (byte offsets, bit positions for tip switch, coordinate ranges, etc.).

Contributions adding support for additional devices are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

## Clone the Repository

```bash
git clone https://github.com/pwhizzard/touch-redirect-mac.git
cd touch-redirect-mac
```

## Open the Project

Touch Redirect is built using Swift Package Manager.

```bash
open TouchRedirect/Package.swift
```

## Build and Run

1. In Xcode, select the **TouchRedirect** scheme.
2. Choose **My Mac** as the run destination.
3. Press **Cmd + R** to build and run.

## Permissions

The app requires:

- **Accessibility** (to inject cursor and keyboard events)
- **Input Monitoring** (for HID device access)

Grant via: **System Settings → Privacy & Security**.

## Code Signing (Development)

For local development, automatic signing is sufficient:

1. In Xcode, open **Signing & Capabilities**
2. Enable **Automatically manage signing**
3. Select your Personal Team

## Running the Built App

After building, the app will be ad-hoc signed (not notarized). macOS Gatekeeper will block it by default.

**To run the app for the first time:**

1. Locate the built app (in Xcode's Products folder or `TouchRedirect.app`)
2. **Right-click** (or Control-click) on the app
3. Select **Open** from the context menu
4. You'll see a dialog saying "Apple could not verify..." — click **Done**
5. Go to **System Settings → Privacy & Security**
6. Scroll down to find **"TouchRedirect" was blocked** and click **Open Anyway**
7. Click **Open** in the final confirmation dialog

You only need to do this once per build. Subsequent launches will work normally.

## Troubleshooting

- **App won't detect the device**: Quit WebexHelper if it's holding the HID device:
  ```bash
  killall WebexHelper
  ```
- **Permission issues**: Make sure Accessibility and Input Monitoring are granted.

## Legacy Xcode Project (Optional)

There is also an older Xcode project under `TouchRedirectMac/`. It is not
the primary build path, but it can be opened if needed:

```bash
open TouchRedirectMac/TouchRedirectMac.xcodeproj
```
