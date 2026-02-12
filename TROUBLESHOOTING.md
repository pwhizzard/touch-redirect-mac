# TouchRedirect Troubleshooting Guide

This guide helps diagnose and fix connection issues between TouchRedirect and the Cisco WebEx Desk Pro.

## Confirmed Working Hardware

| Mac Model | Chip | macOS Version | Status |
|-----------|------|---------------|--------|
| Mac Mini | Apple M4 | macOS 15+ | ✅ Confirmed Working |
| MacBook Pro | Apple M1 | macOS 15+ | ✅ Confirmed Working |

---

## Quick Diagnosis Checklist

Before diving deep, check these common issues:

- [ ] USB-C cable is connected from Mac to Desk Pro
- [ ] TouchRedirect has Accessibility permissions granted
- [ ] TouchRedirect has Input Monitoring permissions granted
- [ ] No conflicting driver extensions are installed (see below)

---

## Step 1: Verify USB Device Detection

First, confirm your Mac sees the Desk Pro HID device at the USB level:

```bash
ioreg -p IOUSB -w 0 | grep -i "desk"
```

**Expected output:**
```
+-o Desk Pro HID Device@02120000
+-o Desk Pro Web Camera@02130000
```

If you see both devices, the USB connection is working. If not:
- Try a different USB-C port
- Try a different USB-C cable
- Check that the Desk Pro is powered on

---

## Step 2: Check for Conflicting Driver Extensions

**This is the most common cause of connection failures.**

Third-party driver extensions can claim exclusive access to the Desk Pro HID device, preventing TouchRedirect from connecting.

### Check installed driver extensions:

```bash
systemextensionsctl list
```

### Known Conflicting Extensions:

| Extension | Bundle ID | Solution |
|-----------|-----------|----------|
| **UPPD / Touch-Base** | `com.touch-base.updd-system-extension-dext` | Disable or uninstall |
| Logitech G HUB HID | `com.logi.ghub.hidfilter` | Usually OK, but can conflict |

### How to Disable a Conflicting Extension:

1. Open **System Settings**
2. Go to **General** → **Login Items & Extensions**
3. Click **Driver Extensions**
4. Find the conflicting extension
5. **Toggle it OFF**
6. **Restart your Mac**

---

## Step 3: Verify HID Device Configuration

Check if the Desk Pro HID device is properly configured:

```bash
ioreg -p IOUSB -w 0 -l | grep -A 35 "Desk Pro HID"
```

**Look for these properties:**
- `idVendor` = 1446 (0x05a6 in hex - Cisco)
- `idProduct` = 2821 (0x0b05 in hex - Desk Pro)
- `kUSBCurrentConfiguration` = 1 (device is configured)

**If `kUSBCurrentConfiguration` is missing:** Another driver is blocking the device. Go back to Step 2.

---

## Step 4: Check for Driver Blocking in Detail

This command shows what's attached to the HID device:

```bash
ioreg -p IOService -w 0 -l | grep -B 5 -A 50 "Desk Pro HID" | head -80
```

**Warning signs to look for:**

```
+-o IOService  <class IOService, ... !registered, !matched ...>
    "CFBundleIdentifier" = "com.touch-base.updd-system-extension-dext"
    "IOProbeScore" = 90000
```

If you see a third-party bundle identifier with `!registered, !matched`, that driver is claiming but not properly using the device.

---

## Step 5: Verify Permissions

### Check Accessibility Permission:

TouchRedirect needs Accessibility permission to move the mouse cursor.

1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Ensure **TouchRedirect** is listed and enabled

### Check Input Monitoring Permission:

TouchRedirect needs Input Monitoring permission to receive HID events.

1. Open **System Settings** → **Privacy & Security** → **Input Monitoring**
2. Ensure **TouchRedirect** is listed and enabled

---

## Step 6: Check for HID Interface

Verify the Desk Pro appears as an HID device (not just a USB device):

```bash
ioreg -r -c IOHIDDevice | grep -B 5 -A 25 "Desk Pro"
```

If the Desk Pro doesn't appear here but does appear in Step 1, a driver extension is blocking it.

---

## Common Issues and Solutions

### Issue: "Status: Disconnected" in TouchRedirect

**Cause:** The Desk Pro HID device is detected but something is preventing access.

**Solutions:**
1. Check for conflicting driver extensions (Step 2)
2. Verify permissions (Step 5)
3. Restart TouchRedirect
4. Restart your Mac

---

### Issue: Desk Pro Not Showing in USB Device List

**Cause:** Hardware connection issue.

**Solutions:**
1. Try a different USB-C port on your Mac
2. Try a different USB-C cable
3. Check that the Desk Pro is powered on and not in standby
4. Disconnect and reconnect the cable

---

### Issue: UPPD/Touch-Base Driver Blocking Device

**Cause:** The UPPD (Universal Pointer Device Driver) claims exclusive access to touch devices.

**Solution:**
1. Open **System Settings** → **General** → **Login Items & Extensions**
2. Click **Driver Extensions**
3. Disable **com.touch-base.updd-system-extension-dext**
4. Restart your Mac

**To fully uninstall UPPD:**
```bash
# List the extension first
systemextensionsctl list | grep updd

# Uninstall (requires admin password)
sudo systemextensionsctl uninstall U86H28HG4S com.touch-base.updd-system-extension-dext
```

---

### Issue: Touch Works But Cursor is Offset

**Cause:** Calibration is needed.

**Solution:**
1. Click the TouchRedirect menu bar icon
2. Select **Calibrate...**
3. Follow the on-screen calibration prompts
4. Touch each corner when prompted

---

## Diagnostic Commands Reference

### Full USB Device Tree
```bash
ioreg -p IOUSB -w 0
```

### Detailed Desk Pro Info
```bash
ioreg -p IOUSB -w 0 -l | grep -A 40 "Desk Pro HID"
```

### All System Extensions
```bash
systemextensionsctl list
```

### Check What's Using the Device
```bash
ioreg -p IOService -w 0 -l | grep -B 5 -A 50 "Desk Pro HID"
```

### All HID Devices
```bash
ioreg -r -c IOHIDDevice | grep -E "Product|Vendor|UsagePage"
```

### Check for Cisco Processes
```bash
ps aux | grep -i cisco | grep -v grep
```

---

## Getting Help

If you're still having issues after following this guide:

1. Run the diagnostic commands above
2. Save the output to a file
3. Open an issue on the project repository with:
   - Your Mac model and chip (M1, M2, M4, etc.)
   - macOS version
   - The diagnostic output
   - Description of the issue

---

## Technical Details

### Expected Device Properties

| Property | Value | Notes |
|----------|-------|-------|
| Vendor ID | 0x05a6 (1446) | Cisco Systems, Inc. |
| Product ID | 0x0b05 (2821) | Desk Pro HID Device |
| Usage Page | 0x0D | Digitizer |
| Usage | 0x04 | Touch Screen |

### How TouchRedirect Works

1. Uses IOKit's `IOHIDManager` to detect USB HID devices
2. Matches devices with Vendor ID 0x05a6 and Product ID 0x0b05
3. Filters for Usage Page 0x0D (Digitizer) and Usage 0x04 (Touch Screen)
4. Receives touch reports and translates them to mouse events
5. Injects mouse events using Core Graphics APIs
