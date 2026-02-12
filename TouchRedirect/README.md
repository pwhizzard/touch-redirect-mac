# TouchRedirect

This is the Swift Package Manager project for Touch Redirect.

For full documentation, see the [main README](../README.md).

## Quick Build

```bash
swift build -c release
bash Scripts/build-app.sh
```

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
