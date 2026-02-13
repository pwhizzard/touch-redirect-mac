# TouchRedirect

This is the Swift Package Manager project for Touch Redirect.

For full documentation, see the [main README](../README.md).

## Quick Build

```bash
swift build -c release
bash Scripts/build-app.sh
```

## Local Deploy Workflow

```bash
# Build release binary
swift build -c release

# Stop app if running
killall TouchRedirect

# Copy into /Applications bundle
cp .build/release/TouchRedirect /Applications/TouchRedirect.app/Contents/MacOS/TouchRedirect
cp Sources/TouchRedirect/Info.plist /Applications/TouchRedirect.app/Contents/Info.plist

# Re-sign and relaunch
codesign --force --deep --sign - /Applications/TouchRedirect.app
open /Applications/TouchRedirect.app
```

If re-signing changes code identity, macOS may ask for Accessibility/Input Monitoring permissions again.

## Project Structure

```
Sources/TouchRedirect/
├── main.swift           # Entry point
├── AppDelegate.swift    # App lifecycle, menu bar, calibration flow
├── HIDManager.swift     # USB HID device detection
├── TouchParser.swift    # HID report parsing
├── Mapper.swift         # Coordinate transformation
├── GestureEngine.swift  # Multi-touch gesture recognition
├── Injector.swift       # CGEvent injection
├── ScreenManager.swift  # Display detection and management
├── CalibrationWindow.swift  # Calibration UI
├── SettingsWindow.swift # Settings and onboarding UI
├── Config.swift         # User preferences (UserDefaults)
└── LaunchAtLogin.swift  # Auto-launch support
```

## License

GNU General Public License v3.0 — see [LICENSE](../LICENSE).
