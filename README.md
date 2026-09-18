# Awqat · Prayer Times for Omarchy

<img src="logo.svg" alt="Awqat: dawn in a prayer arch" width="64" height="64">

**A simple, lightweight prayer-times plugin for Omarchy, powered by Rust.**

The everyday prayer features you need, in a quiet, compact bar widget:

- **Automatic location** by IP, with manual city selection and calculation-method settings.
- **All five prayers and sunrise**, Arabic labels, Hijri date, and a live next-prayer countdown.
- **Your bar, your format:** ready-made layouts, live previews, custom tokens, and 12/24-hour time.
- **Optional prayer alerts:** desktop notifications, gentle tones, full adhan, or your own local audio.
- **Built to stay light:** a roughly 724 KiB native Rust helper, no persistent helper daemon, shared state across monitors, and a panel that loads only when opened.
- **Resilient daily use:** cached schedules during network outages, automatic retries, and duplicate-alert suppression.

The native QML interface follows your Omarchy theme. Rust handles schedules, caching, and alerts; Python is not required at runtime. The binary size above is for the ARM64 build and excludes shared system libraries, the Omarchy shell, and optional audio files.

Click the Awqat prayer-arch icon and next prayer in the bar to open. The gear opens three settings tabs: **Location**, **Bar**, and **Alerts**. Click **12H / 24H** to switch time format. The refresh button (or middle-click on the bar widget) detects location again and refreshes the schedule.

## Preview

<img src="preview.png" alt="Awqat on Omarchy: Riyadh prayer times, Arabic labels, next-prayer countdown, and Hijri date" width="348">

Actual Awqat panel on Omarchy. Colors follow the active desktop theme.

### Logo concepts

[Explore 36 logo concepts](docs/logo-gallery.html): download the HTML file and open it in a browser. It works offline, with day/night themes, six ink palettes, adjustable bar-size previews, favorites, and individual SVG downloads. The installed logo remains the current prayer arch until a new direction is chosen.

## Install

Requires Omarchy’s Quickshell plugin system, system libcurl with HTTPS support, and the system timezone database. Desktop notifications use `notify-send`; optional audio uses `mpv`. The runtime helper is Rust; Python is not required. Node is only needed for JavaScript development tests.

Build tools: Rust/Cargo 1.89+, a C compiler, and pkg-config. On Omarchy:

```sh
omarchy pkg add rust base-devel
omarchy plugin add https://github.com/iYassr/awqat
cd ~/.config/omarchy/plugins/yasserdo.awqat
./build.sh
omarchy plugin enable yasserdo.awqat
```

If the installer offers to enable the plugin, finish the build before using it. `build.sh` downloads the dependencies pinned in `Cargo.lock`, creates an optimized native `bin/awqat-core`, and removes its temporary build output. The launcher checks source hashes before running the compiled helper, so source updates require a rebuild. The compiler and Cargo registry cache are development tools; they are not part of the runtime helper. No background daemon or automatic build/download hook is installed.

For a local checkout, copy this folder to `~/.config/omarchy/plugins/yasserdo.awqat/`, run `./build.sh` there, then run:

```sh
omarchy plugin validate ~/.config/omarchy/plugins/yasserdo.awqat
omarchy-shell shell rescanPlugins
omarchy plugin enable yasserdo.awqat
```

After updating, rebuild the helper:

```sh
omarchy plugin update yasserdo.awqat
cd ~/.config/omarchy/plugins/yasserdo.awqat
./build.sh
omarchy-shell yasserdo.awqat refresh
```

Settings, downloaded audio, and the delivery ledger carry over from the Python version. Compatible existing schedule caches are reused. Native binaries are built for the current machine; do not copy an ARM64 binary onto an x86-64 system.

The folder must contain `manifest.json` directly. Enabling adds the widget to the bar; the default section is **right**. Existing widgets and settings are preserved. This plugin targets the native Quickshell shell, rather than older Waybar configurations.

## Omarchy integration

Awqat follows the plugin contract shipped with Omarchy in `/usr/share/omarchy/shell/plugins/README.md` and checked by `omarchy plugin validate`:

- A schema version 1 manifest declares the namespaced ID `yasserdo.awqat`, the `bar-widget` kind, and a relative `BarWidget.qml` entry point.
- The entry point extends `Ui.BarWidget` and uses native `Ui.WidgetButton`, `Ui.Panel`, and `Ui.KeyboardPanel` components. Colors and spacing come from the shell theme.
- Settings are stored inline in the bar entry through the shell API. The plugin is installed only under the user plugin directory; it does not modify packaged Omarchy files.
- The icon is a small, static vector that inherits the surrounding text color. `logo.svg` contains the same geometry for documentation and reuse.
- `allowMultiple: false` prevents duplicate entries. A shared singleton handles multiple monitors without running a separate daemon.

## Troubleshooting and removal

If the widget does not appear, run the validation and rescan commands above, then enable it again. After editing a nested QML component, use `omarchy restart shell` if the old version remains visible.

For incorrect location, inspect the detected city and choose a manual city in **Location**. For network errors, use **Retry** or refresh; cached schedules remain available when possible. For silent audio, check **Alerts**, volume, the selected audio file, and that `mpv` is installed.

Disable with `omarchy plugin disable yasserdo.awqat`. To uninstall, use `omarchy plugin remove yasserdo.awqat`; this removes the plugin folder, including any local code changes. Cache and alert history are stored separately at the paths documented below.

## Location and calculations

Automatic location uses [ipwho.is](https://ipwhois.io/documentation). It checks every 30 minutes, or immediately on refresh. The detected city is always visible; VPNs and carrier gateways may affect its accuracy. Only city, coordinates, country, and timezone are cached, not the IP or ISP. A manual city override uses Open-Meteo geocoding and displays the resolved city.

Prayer times come from [AlAdhan](https://aladhan.com/prayer-times-api), requested using coordinates and the location's timezone. Automatic method selects Umm al-Qura for Saudi Arabia; elsewhere AlAdhan selects the nearest calculation authority. Settings offer alternative methods and Standard/Hanafi Asr. These are calculated prayer start times; local mosque iqamah times may differ.

Today, yesterday, and tomorrow are cached independently under `~/.cache/omarchy-awqat/` (or `$XDG_CACHE_HOME/omarchy-awqat`). Offline mode is labeled explicitly. The next prayer excludes sunrise and advances to tomorrow's Fajr after Isha. A failed tomorrow request does not hide today's timetable. Settings are persisted inline in the plugin's `~/.config/omarchy/shell.json` bar entry.

```json
{"id":"yasserdo.awqat","locationMode":"auto","method":"auto","school":"0","clock24":false}
```

## Bar formatting

The **Bar** tab offers nine presets, each with its own live example. Choose prayer + time, time only, name only, countdown, prayer + countdown, Arabic + time, time + name, icon only, or a custom format. The Awqat vector icon can be hidden. Long bar text is ellipsized so it cannot crowd out other widgets.

Custom examples:

```text
{name} {h}::{mm}:{ampm}    → Dhuhr 11::47:am
{time24}                    → 11:47
{arabic} · {time}           → الظهر · 11:47 AM
{name} in {remaining}       → Dhuhr in 2h 3m
{HH}:{mm} · {city}          → 11:47 · Riyadh
```

Supported tokens: `{name}`, `{arabic}`, `{short}`, `{time}`, `{time24}`, `{time12}`, `{h}`, `{hh}`, `{H}`, `{HH}`, `{mm}`, `{ampm}`, `{AMPM}`, `{remaining}`, `{remainingClock}`, `{city}`, and `{icon}`. `h/hh` use 12-hour time; `H/HH` use 24-hour time; doubled hour letters add a leading zero. `{time}` follows the 12H/24H setting. Custom separators and literal text are supported. Unknown or unclosed tokens are explained before saving.

## Notifications and audio

In **Alerts**, desktop notifications and sound are independent options. Defaults are notifications off and sound **Silent**. Options include a locally synthesized gentle chime or soft bell, two full adhan recordings, or a local MP3/WAV/OGG/FLAC/M4A/Opus file. Preview, Stop, a keyboard-adjustable volume slider, and Send test notification are available before saving. Closing the panel does not stop an active adhan; use **Stop prayer audio** or the IPC command below.

Full adhan recordings are fetched on selection/preview from [AlAdhan’s download page](https://aladhan.com/download-adhans): Ahmad al-Nafees (`a1.mp3`) and Mishary Rashid Alafasy (`a9.mp3`). They are downloaded on demand into the local audio cache, not distributed under this repository’s MIT license. The original recordings remain subject to their respective owners’ terms.

Alerts apply to the five prayers, not sunrise. They require a running Omarchy shell and an awake device. Events more than 90 seconds old are not replayed after resume. An atomic delivery ledger in `$XDG_STATE_HOME/omarchy-awqat` (default `~/.local/state/omarchy-awqat`) prevents duplicates across reloads and monitors. Desktop notifications follow the system notification settings; audio follows the explicit Awqat sound/volume choice. A Fajr-specific recording can be provided through the custom audio option; the bundled choices are general adhan recordings.

## Performance and reliability

- One shared updater and clock across monitors; the panel is created on demand and destroyed after closing.
- Closed-panel checks run at most once a minute, with an earlier wake at the next prayer boundary. An open countdown or `{remainingClock}` in the bar requests second updates.
- Automatic location is checked every 30 minutes; manual locations need no recurring IP lookups. Dated prayer schedules are reused for seven days, so a steady location normally fetches only the next uncached day.
- Network helpers exit after their work. HTTPS requests reject redirects and have size and connection/transfer limits; failures retry with delays from 1 to 15 minutes. Successful cached data remains available offline.
- JSON cache is bounded to 96 files, 2 MiB, and 35 days. Audio is separate: two optional adhan tracks, each capped at 8 MiB, plus two tones under 80 KiB each. The delivery ledger retains at most 32 recent events.
- Cache writes are atomic. Corrupt cached data is validated and refetched; cache write failures do not discard valid network responses. Concurrent helper invocations share a lock.

A local ARM64 comparison across 15 warm runs measured **11 ms median / 10.8 MiB peak RSS** for the Rust helper through its launcher, versus **59 ms / 25.2 MiB** for the previous Python helper. The optimized binary is approximately **724 KiB**, dynamically linked to the system libcurl. This measures temporary helper usage, not the whole Omarchy shell, compiler, network transfer, or audio playback. See [REVIEW.md](REVIEW.md) for methodology and limits.

## Commands

```sh
omarchy-shell yasserdo.awqat open
omarchy-shell yasserdo.awqat settings
omarchy-shell yasserdo.awqat settingsTab bar
omarchy-shell yasserdo.awqat settingsTab alerts
omarchy-shell yasserdo.awqat testNotification
omarchy-shell yasserdo.awqat preview chime 35
omarchy-shell yasserdo.awqat stopAudio
omarchy-shell yasserdo.awqat refresh
omarchy-shell yasserdo.awqat status
omarchy plugin disable yasserdo.awqat
```

## Verification

```sh
cargo test --locked --target-dir /tmp/awqat-test-build
cargo clippy --locked --target-dir /tmp/awqat-test-build --all-targets -- -D warnings
cargo fmt --check
node tests/model.test.cjs
python3 tests/reliability_cli.py  # Optional CLI regressions; build the helper first
omarchy plugin validate .
```

The standard suite includes 41 Rust tests and 39 JavaScript checks covering cache isolation/limits/corruption, offline fallback, timezone/year rollover, partial API failure, formatting, retry backoff, duplicate suppression, late-wake behavior, disabled alerts, private storage, atomic-write cleanup, and tone generation. An additional HTTPS integration test covers certificates, hostnames, redirects, timeouts, and response-size limits. Run `python3 tests/security_transport.py` with Python 3 and OpenSSL installed; these are optional test tools, not runtime requirements. The QML panel also needs a running Omarchy shell for visual verification. See [UX-AUDIT.md](UX-AUDIT.md) for usability coverage, [SECURITY.md](SECURITY.md) for security boundaries and privacy, and [REVIEW.md](REVIEW.md) for reliability, performance, and code review findings.

## License

Plugin code and vector artwork are available under the [MIT license](LICENSE). Downloaded adhan recordings are external assets; see the audio attribution above.

The [plugin comparison](PLUGIN-COMPARISON.md) records lessons from popular community plugins and the reliability changes applied in 1.2.2. Python is optional for the CLI and HTTPS test harnesses only.
