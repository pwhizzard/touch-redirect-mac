#!/bin/bash
#
# Build Verification Script for TouchRedirect
#
# Verifies that the built application has correct entitlements,
# permissions, and configuration for USB HID device access.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "═══════════════════════════════════════════════════════════"
echo "TouchRedirect - Build Verification"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Find the app
APP_PATH=""

if [ -n "$1" ]; then
    APP_PATH="$1"
elif [ -f "TouchRedirect.app/Contents/MacOS/TouchRedirect" ]; then
    APP_PATH="TouchRedirect.app"
elif [ -f "../TouchRedirect.app/Contents/MacOS/TouchRedirect" ]; then
    APP_PATH="../TouchRedirect.app"
elif [ -f "/Applications/TouchRedirect.app/Contents/MacOS/TouchRedirect" ]; then
    APP_PATH="/Applications/TouchRedirect.app"
else
    echo "${RED}❌ Error: TouchRedirect.app not found${NC}"
    echo ""
    echo "Usage: $0 [path/to/TouchRedirect.app]"
    echo ""
    echo "Or run from a directory containing TouchRedirect.app"
    exit 1
fi

echo "Verifying: $APP_PATH"
echo ""
echo "─────────────────────────────────────────────────────────"
echo ""

# Check 1: App exists and is executable
echo "Check 1: Application Structure"
if [ -f "$APP_PATH/Contents/MacOS/TouchRedirect" ]; then
    echo "  ${GREEN}✓${NC} Executable found"
else
    echo "  ${RED}❌ Executable missing${NC}"
    exit 1
fi

if [ -f "$APP_PATH/Contents/Info.plist" ]; then
    echo "  ${GREEN}✓${NC} Info.plist found"
else
    echo "  ${RED}❌ Info.plist missing${NC}"
    exit 1
fi

echo ""

# Check 2: Code Signing
echo "Check 2: Code Signing"
if codesign -v "$APP_PATH" 2>/dev/null; then
    echo "  ${GREEN}✓${NC} Code signature valid"
    
    # Get signing identity
    IDENTITY=$(codesign -dvv "$APP_PATH" 2>&1 | grep "Authority" | head -1 | cut -d= -f2)
    echo "  Identity: $IDENTITY"
else
    echo "  ${YELLOW}⚠️  Code signature invalid or ad-hoc${NC}"
    echo "     (This is normal for development builds)"
fi

echo ""

# Check 3: Entitlements
echo "Check 3: Entitlements"

ENTITLEMENTS=$(codesign -d --entitlements - "$APP_PATH" 2>/dev/null | plutil -convert xml1 -o - -)

check_entitlement() {
    local key=$1
    local expected=$2
    local description=$3
    
    if echo "$ENTITLEMENTS" | grep -q "<key>$key</key>"; then
        local value=$(echo "$ENTITLEMENTS" | grep -A1 "<key>$key</key>" | tail -1 | sed 's/.*<\(.*\)>.*/\1/')
        
        if [ "$value" = "$expected" ]; then
            echo "  ${GREEN}✓${NC} $key = $expected"
            echo "     $description"
            return 0
        else
            echo "  ${RED}❌${NC} $key = $value (expected: $expected)"
            echo "     $description"
            return 1
        fi
    else
        echo "  ${RED}❌${NC} $key MISSING (expected: $expected)"
        echo "     $description"
        return 1
    fi
}

ENTITLEMENTS_OK=true

if ! check_entitlement "com.apple.security.device.usb" "true" "Required for USB HID device access"; then
    ENTITLEMENTS_OK=false
fi

if ! check_entitlement "com.apple.security.app-sandbox" "false" "Must be disabled (sandboxed apps cannot access raw HID)"; then
    ENTITLEMENTS_OK=false
fi

echo ""

# Check 4: Info.plist Configuration
echo "Check 4: Info.plist Configuration"

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "")
if [ -n "$BUNDLE_ID" ]; then
    echo "  ${GREEN}✓${NC} Bundle ID: $BUNDLE_ID"
else
    echo "  ${RED}❌ Bundle ID missing${NC}"
    ENTITLEMENTS_OK=false
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "")
if [ -n "$VERSION" ]; then
    echo "  ${GREEN}✓${NC} Version: $VERSION"
else
    echo "  ${YELLOW}⚠️  Version missing${NC}"
fi

MIN_OS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "")
if [ -n "$MIN_OS" ]; then
    echo "  ${GREEN}✓${NC} Minimum macOS: $MIN_OS"
else
    echo "  ${YELLOW}⚠️  Minimum macOS version not specified${NC}"
fi

echo ""

# Check 5: Architecture
echo "Check 5: Architecture Support"

ARCH_INFO=$(lipo -info "$APP_PATH/Contents/MacOS/TouchRedirect" 2>/dev/null)
echo "  $ARCH_INFO"

if echo "$ARCH_INFO" | grep -q "arm64"; then
    echo "  ${GREEN}✓${NC} Apple Silicon (arm64) supported"
fi

if echo "$ARCH_INFO" | grep -q "x86_64"; then
    echo "  ${GREEN}✓${NC} Intel (x86_64) supported"
fi

echo ""

# Check 6: File Permissions
echo "Check 6: File Permissions"

if [ -x "$APP_PATH/Contents/MacOS/TouchRedirect" ]; then
    echo "  ${GREEN}✓${NC} Executable has execute permission"
else
    echo "  ${RED}❌ Executable lacks execute permission${NC}"
    ENTITLEMENTS_OK=false
fi

echo ""

# Summary
echo "═══════════════════════════════════════════════════════════"
echo "Summary"
echo "═══════════════════════════════════════════════════════════"
echo ""

if [ "$ENTITLEMENTS_OK" = true ]; then
    echo "${GREEN}✓ BUILD VERIFICATION PASSED${NC}"
    echo ""
    echo "The application is properly configured for USB HID access."
    echo ""
    echo "Next steps:"
    echo "  1. Copy to /Applications:"
    echo "     cp -r \"$APP_PATH\" /Applications/"
    echo ""
    echo "  2. On first launch, right-click → Open to bypass Gatekeeper"
    echo ""
    echo "  3. Grant required permissions:"
    echo "     - Accessibility (System Settings → Privacy & Security)"
    echo "     - Input Monitoring (System Settings → Privacy & Security)"
    echo ""
else
    echo "${RED}❌ BUILD VERIFICATION FAILED${NC}"
    echo ""
    echo "The application has missing or incorrect entitlements."
    echo ""
    echo "Common fixes:"
    echo ""
    echo "  1. Ensure TouchRedirect.entitlements file exists:"
    echo "     TouchRedirect/TouchRedirect.entitlements"
    echo ""
    echo "  2. In Xcode, verify Signing & Capabilities:"
    echo "     - Select TouchRedirect target"
    echo "     - Go to Signing & Capabilities tab"
    echo "     - Ensure entitlements file is linked"
    echo ""
    echo "  3. Rebuild with proper code signing:"
    echo "     xcodebuild -scheme TouchRedirect \\"
    echo "       CODE_SIGN_ENTITLEMENTS=TouchRedirect.entitlements"
    echo ""
    exit 1
fi

echo "═══════════════════════════════════════════════════════════"
