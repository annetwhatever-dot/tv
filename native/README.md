# TV Glow — native Apple apps

The macOS SwiftUI app controls Anna’s LG C1 OLED brightness and Sonos Arc Ultra volume directly over the home network. It has a main window, a menu-bar panel, brightness presets, precise +/- controls, volume and mute. The native apps do not use the Python/web server.

The installed Mac app is `/Users/anna/Applications/TV Glow.app`. Open it from Finder, Spotlight or Launchpad. Click the sun in the menu bar for quick controls. **Connections** lets you update each device’s IP address or forget this app’s TV pairing.

Debug builds use the display name **TV Glow Dev** and bundle ID `com.anna.tvglow.mac.debug`; Release uses **TV Glow** and `com.anna.tvglow.mac`. Their sandbox preferences and Keychain services are separate. The iOS Debug bundle ID likewise ends in `.debug`. Install Debug builds as `TV Glow Dev.app`, never over the Release app. Pair each build independently. The earlier shared `com.anna.tvglow.pairing` entry is no longer queried or migrated, so it can be denied without entering a password.

Ad hoc signatures change when app code changes. Separate IDs prevent development builds from touching production pairings; a stable Apple development/distribution signing identity is the longer-term solution for Keychain trust across signed app updates.

Known devices:

- LG OLED65C1RLA: `192.168.2.159`
- Living Room Sonos Arc Ultra: `192.168.0.206`

The addresses are editable and saved after a successful connection. macOS may ask for local network access. The first native TV pairing also needs **Accept** on the TV; the native app’s pairing key is stored in Keychain. Opening, reconnecting or refreshing only reads settings. Brightness is sent when the slider is released or a button is pressed, then read back from the TV. Volume and mute are likewise verified with the soundbar. Requests to public or loopback addresses are rejected.

## Build and test macOS

No package dependencies or simulator runtime are required. Xcode 26.3 is available on this Mac. The source targets macOS 14+ and iOS 17+.

```sh
cd /Users/anna/Developer/tv-brightness/native
xcodebuild -project TVGlow.xcodeproj -scheme 'TV Glow macOS' \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath DerivedData build

xcodebuild -project TVGlow.xcodeproj -scheme 'TV Glow macOS' \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath DerivedData test
```

The release `.app` is under `DerivedData/Build/Products/Release/`. Quit the installed app before replacing it with a new release build. Release builds use the app sandbox with the outgoing network entitlement and an ad hoc signature for this Mac. This is a personal local build, not a notarized distribution.

Tests use fake devices and never change real brightness, volume or mute. They cover connecting without writes, 0% brightness, readback failures, independent Sonos control, XML parsing, invalid values and local address validation.

## iOS groundwork

`TV Glow iOS` uses the same SwiftUI views and device clients, with a vertical phone layout. The menu-bar scene is macOS-only. An iPhone build can be compiled without starting a simulator:

```sh
xcodebuild -project TVGlow.xcodeproj -scheme 'TV Glow iOS' \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

The iOS target is groundwork, not yet delivered. This Mac currently reports that the iOS 26.2 platform component is missing, even though `xcodebuild -showsdks` lists its SDK. A generic-device build stops at destination selection; no platform downloads or simulator bootstrap were started. Installing on a physical iPhone will also require selecting an Apple development team in Xcode. No valid signing identity was present when the project was created. Foreground/background behavior and on-device permission prompts still need physical-iPhone validation.

## Verified on Anna’s devices

The native release connected to both devices. A brightness command of 0% was accepted and read back as 0%. Sonos volume was lowered from 45 to 44 through the native app, then restored to 45 and read back. Live tests never increased TV brightness. Six macOS unit tests passed. Brightness fallback handles the C1’s 500/unsupported-key response to direct writes.

## Protocols and attribution

- LG webOS SSAP WebSocket on the TV’s local port 3000. A rejected direct picture write uses the established local notification callback method to apply only the ordinary `backlight` picture setting. No calibration or service-menu features are exposed.
- Sonos local UPnP `RenderingControl` on port 1400: `GetVolume`, `SetVolume`, `GetMute`, `SetMute`. This targets the Living Room soundbar. It does not change whole-house Sonos group volume.
- `WebOSManifest.json` and the compatible LG fallback follow [bscpylgtv](https://github.com/chros73/bscpylgtv); its MIT notice is retained in `TVGlow/Resources/WebOS-LICENSE.txt` and in the app bundle. No private pairing keys are embedded in source or resources.

`scripts/generate_project.py` reproducibly generates the Xcode project and icon catalogs. Regeneration needs Pillow, already present in the Mac’s Python environment. Normal Xcode builds do not run that generator.
