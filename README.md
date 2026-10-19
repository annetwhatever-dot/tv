# TV Glow

The native SwiftUI Mac app is installed at `/Users/anna/Applications/TV Glow.app`. It adds direct Sonos Arc Ultra volume/mute control and a menu-bar panel. See [native/README.md](native/README.md) and open `native/TVGlow.xcodeproj` for the shared macOS/iOS source. The native Mac app connects directly to both devices and does not need this web server.

A local Safari-friendly OLED brightness controller for Anna’s LG C1. The Mac talks to the TV through `bscpylgtv`; the phone talks to the Mac. Only the normal picture setting `backlight` (OLED Pixel Brightness) is changed. Presets are Night 15, Everyday 45 and Bright 80. TV settings can be specific to the active input, picture mode and SDR/HDR/Dolby Vision content.

## Run

```sh
cd /Users/anna/Developer/tv-brightness
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python run.py
```

The server binds to `0.0.0.0:8765`. Open `http://<Mac Wi-Fi IPv4>:8765` on the phone, tap **Find my TV**, and accept the pairing request on the television. If discovery fails, enter its local IPv4 address. Network paths on the C1 may be under General → Network or General → Devices → TV Management. No developer mode or TV app installation is required.

Keep the Mac awake, and the TV, Mac and phone on the same home network. Guest networks with client isolation will prevent control. In Safari, Share → Add to Home Screen makes a convenient launcher. Plain HTTP on a LAN does not support offline service workers, so the Mac must be available.

You can also double-click **Start TV Glow.command** to launch it again. The launcher saves the reachable LAN address, starts the PID-bound Snippets watcher, refreshes the address if the Mac changes networks, and marks the entry offline on shutdown. Stop with Ctrl+C in its terminal. Run a single copy at a time.

The interface is accessible to devices on that home network. Pairing keys are stored in `.state/` (private directory, excluded from version control) and are never sent to browsers. Writes require a same-origin custom header. Only private IPv4 TV destinations are accepted. Current brightness is read back after writes; the UI explicitly indicates if a setting cannot be confirmed. If OLED light does not change, check the TV’s Energy Saving setting.

For every launch, save the verified LAN URL using `/Users/anna/.agents/skills/record-deployment-links/scripts/save_project_link.py` with project **TV Glow**, then run the skill’s PID-bound watcher. Refresh the saved URL if the Mac’s LAN IP changes. Logs and state stay local.
