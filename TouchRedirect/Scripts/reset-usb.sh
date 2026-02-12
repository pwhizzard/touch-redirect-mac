#!/bin/bash
#
# USB Reset Helper Script for TouchRedirect
#
# This script helps troubleshoot USB HID device connection issues
# by killing conflicting processes and providing guidance for
# hardware-level troubleshooting.
#

set -e

echo "═══════════════════════════════════════════════════════════"
echo "TouchRedirect - USB Reset Helper"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Check if running with sufficient privileges
if [ "$EUID" -eq 0 ]; then
    echo "⚠️  Warning: Running as root. This script does not require sudo."
    echo ""
fi

# Step 1: Kill conflicting processes
echo "Step 1: Checking for conflicting processes..."
echo ""

KILLED_ANY=false

if pgrep -x "WebexHelper" > /dev/null; then
    echo "  Found: WebexHelper"
    killall WebexHelper 2>/dev/null || true
    echo "  ✓ Killed WebexHelper"
    KILLED_ANY=true
fi

if pgrep -x "UPPD" > /dev/null; then
    echo "  Found: UPPD"
    killall UPPD 2>/dev/null || true
    echo "  ✓ Killed UPPD"
    KILLED_ANY=true
fi

if pgrep -i "cisco" > /dev/null; then
    echo "  Found: Other Cisco processes"
    pkill -i cisco 2>/dev/null || true
    echo "  ✓ Killed Cisco processes"
    KILLED_ANY=true
fi

if [ "$KILLED_ANY" = false ]; then
    echo "  ✓ No conflicting processes found"
fi

echo ""
echo "─────────────────────────────────────────────────────────"
echo ""

# Step 2: Check for UPPD installation
echo "Step 2: Checking for UPPD software..."
echo ""

UPPD_FOUND=false

if [ -d "/Applications/UPPD.app" ]; then
    echo "  ⚠️  UPPD application found in /Applications"
    UPPD_FOUND=true
fi

if ls /Library/Extensions/*uppd* 2>/dev/null; then
    echo "  ⚠️  UPPD kernel extensions found"
    UPPD_FOUND=true
fi

if ls /Library/Extensions/*[Cc]isco* 2>/dev/null; then
    echo "  ⚠️  Cisco kernel extensions found"
    UPPD_FOUND=true
fi

if ls /Library/LaunchDaemons/*uppd* /Library/LaunchDaemons/*cisco* 2>/dev/null; then
    echo "  ⚠️  UPPD/Cisco launch daemons found"
    UPPD_FOUND=true
fi

if [ "$UPPD_FOUND" = true ]; then
    echo ""
    echo "  ⚠️  UPPD software detected!"
    echo "  This software can prevent TouchRedirect from accessing the device."
    echo ""
    echo "  To completely remove UPPD:"
    echo "  1. Run the UPPD uninstaller if available"
    echo "  2. Remove kernel extensions (requires reboot):"
    echo "     sudo rm -rf /Library/Extensions/*uppd*"
    echo "     sudo rm -rf /Library/Extensions/*[Cc]isco*"
    echo "  3. Remove launch daemons:"
    echo "     sudo rm /Library/LaunchDaemons/*uppd*"
    echo "     sudo rm /Library/LaunchDaemons/*cisco*"
    echo "  4. Reboot your Mac"
else
    echo "  ✓ No UPPD software found"
fi

echo ""
echo "─────────────────────────────────────────────────────────"
echo ""

# Step 3: Check USB device presence
echo "Step 3: Checking for Cisco WebEx Desk Pro..."
echo ""

if system_profiler SPUSBDataType 2>/dev/null | grep -i "Cisco" > /dev/null; then
    echo "  ✓ Cisco device found in USB system"
    echo ""
    system_profiler SPUSBDataType | grep -A 10 -i "Cisco" | head -15
else
    echo "  ❌ Cisco device NOT found in USB system"
    echo ""
    echo "  Troubleshooting steps:"
    echo "  1. Verify USB-C cable is data-capable (not charge-only)"
    echo "  2. Try different USB-C ports on your Mac"
    echo "  3. **Try connecting BOTH HDMI and USB-C cables**"
    echo "  4. Power cycle the Desk Pro:"
    echo "     - Unplug power from Desk Pro"
    echo "     - Wait 30 seconds"
    echo "     - Plug power back in"
    echo "     - Wait for full boot"
    echo "     - Connect USB-C to Mac"
    echo ""
fi

echo ""
echo "─────────────────────────────────────────────────────────"
echo ""

# Step 4: Restart TouchRedirect
echo "Step 4: Restarting TouchRedirect..."
echo ""

if pgrep -x "TouchRedirect" > /dev/null; then
    echo "  Stopping TouchRedirect..."
    killall TouchRedirect 2>/dev/null || true
    sleep 2
fi

echo "  ✓ TouchRedirect stopped (if it was running)"
echo ""
echo "  Please manually restart TouchRedirect from Applications"
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "Next Steps:"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "1. Unplug and replug the USB-C cable to the Desk Pro"
echo ""
echo "2. Check if the 'Enable Touch' button appears on the Desk Pro screen"
echo "   - If YES: Touch interface is active, launch TouchRedirect"
echo "   - If NO:  Try connecting BOTH HDMI + USB-C cables"
echo ""
echo "3. Launch TouchRedirect and check if it connects"
echo ""
echo "4. If still not working, run comprehensive diagnostics:"
echo "   - Open TouchRedirect Settings → Diagnostics tab"
echo "   - Click 'Run Full Diagnostics'"
echo "   - Review the output for specific issues"
echo ""
echo "5. For detailed troubleshooting, see:"
echo "   https://github.com/pwhizzard/touch-redirect-mac/blob/main/TROUBLESHOOTING.md"
echo ""
echo "═══════════════════════════════════════════════════════════"
