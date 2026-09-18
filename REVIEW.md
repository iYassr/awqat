# Reliability, performance, and code review

Reviewed on 18 September 2026 before initial GitHub publication. Security findings and trust boundaries are in [SECURITY.md](SECURITY.md); visual and interaction coverage is in [UX-AUDIT.md](UX-AUDIT.md).

## Reliability

- Validated remote/cached location fields and dated prayer timestamps. Prayer events must be ordered; Isha after midnight is supported. Invalid cached timezones, excessive nesting, and future-dated cache timestamps are discarded.
- Kept today's schedule available when adjacent-day requests fail. Location/method/school cache keys remain independent, requests have deadlines, and failures use bounded retry backoff.
- Added shell-side helper deadlines: 110 seconds for the location/schedule helper (including lock wait and sequential requests), 40 seconds for alert preparation. The alert-ledger lock now times out after three seconds.
- Location changes clear queued alerts and stop old audio. Playback volume now recovers from invalid/non-finite configuration values.
- Unknown bar presets, including inherited JavaScript property names, fall back to the default format. Token replacement only reads explicitly supported values.
- Temporary ledger files are removed when replacement fails. Existing atomic cache/ledger writes and persisted duplicate suppression remain in use.

## Speed and footprint

Five fresh-process cached lookups on the development machine measured:

| Measurement | Result |
| --- | --- |
| Median elapsed time | 52.7 ms |
| Range | 47.1–55.3 ms |
| Peak child memory | 25.2 MiB RSS |

These measurements cover the short-lived Python helper, not total Quickshell memory or cold network latency. A warm-cache test confirms no API calls occur. A forced live update succeeded through the stricter transfer rules.

The existing architecture already avoids frequent process startup: one singleton serves all monitors, network helpers exit after work, closed-panel checks run at minute/prayer boundaries, and the panel unloads when closed. Seconds are used only for an open countdown or the explicit seconds-in-bar format. Live status after reload confirmed one initial request, no active playback, no panel instance, and no plugin error. No compiled rewrite or new daemon was needed.

## Code quality

Responsibilities remain separated: `Model.js` contains pure selection/formatting logic; `PrayerState.qml` owns process and timer lifecycle; QML components render the interface; `prayer_times.py` handles schedule I/O; `alerts.py` owns short-lived alert preparation. Runtime Python dependencies remain standard-library only. Added small validation helpers and regression cases at the boundaries instead of introducing a framework.

Configuration and third-party data stay out of shell command strings. Tests use temporary directories and mocked network/notification calls; they do not send desktop notifications or alter the real cache. Documentation now states runtime requirements, privacy, provider dependencies, and delivery limitations.

## Verification

- 32 Python tests and 39 JavaScript assertions passed.
- All QML files parsed; Omarchy manifest validation and Git whitespace checks passed.
- The revised shell loaded without Awqat runtime errors; the idle panel remained unloaded.
- Real cached adhan decoding succeeded with restricted player options. A local playlist disguised as MP3 was rejected.
- Tracked history was scanned for common GitHub/cloud token and private-key patterns; no matches were found.

The changes do not claim exactly-once alert delivery, immunity to provider outages, or universal timezone/high-latitude correctness. A real prayer boundary, multi-day suspend/resume soak test, every theme, and multiple physical monitors were not exercised in this review. Wall-clock measurements are small local samples, not a general performance benchmark.
