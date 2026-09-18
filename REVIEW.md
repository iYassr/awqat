# Reliability, performance, and code review

Reviewed on 18 September 2026; updated after migrating the helper to Rust, with a further security/size review in 1.2.1. Security findings and trust boundaries are in [SECURITY.md](SECURITY.md); visual and interaction coverage is in [UX-AUDIT.md](UX-AUDIT.md).

## Public release review in 1.2.3

The [release-readiness review](RELEASE-READINESS.md) records the latest
findings, fixes, clean-install verification, refreshed dependency check, and
remaining platform/soak-test limits. It adds 15 isolated QML lifecycle checks
and reruns the HTTPS integration fixture.

## Follow-up in 1.2.2

See [PLUGIN-COMPARISON.md](PLUGIN-COMPARISON.md) for the source comparisons,
changes, and accuracy limits. This pass fixed notification/audio-cache
coupling, tightened dated schedules and location modes, simplified schedule
loading, and consolidated QML helper completion and cancellation handling.
41 Rust tests, 39 JavaScript assertions, and three isolated CLI regression
tests passed. The existing HTTPS integration test was not rerun because the
transport and dependencies were unchanged. Strict Clippy, formatting, QML
parsing, manifest validation, and Git whitespace checks passed. Live shell
schedule loading and muted adhan playback/Stop were exercised.

## Reliability

- Validated remote/cached location fields and dated prayer timestamps. Prayer events must be ordered; Isha after midnight is supported. Invalid cached timezones, excessive nesting, and future-dated cache timestamps are discarded.
- Kept today's schedule available when adjacent-day requests fail. Location/method/school cache keys remain independent, requests have deadlines, and failures use bounded retry backoff.
- Added shell-side helper deadlines: 110 seconds for the location/schedule helper (including lock wait and sequential requests), 40 seconds for alert preparation. The alert-ledger lock now times out after three seconds.
- Location changes clear queued alerts and stop old audio. Playback volume now recovers from invalid/non-finite configuration values.
- Unknown bar presets, including inherited JavaScript property names, fall back to the default format. Token replacement only reads explicitly supported values.
- Temporary ledger files are removed when replacement fails. Existing atomic cache/ledger writes and persisted duplicate suppression remain in use.

## Speed and footprint

A comparison on the development machine (Linux ARM64) used a small C parent process with `clock_gettime`, `fork/exec`, and `wait4` to measure 15 fresh helper processes for each implementation against the same warm cache:

| Measurement | Rust (including launcher) | Previous Python |
| --- | --- | --- |
| Median elapsed time | 7.96 ms | 59.04 ms |
| Maximum child RSS | 10.70 MiB | 25.17 MiB |

The first Rust release binary was approximately 764 KiB. Version 1.2.1 reduces it to 724 KiB and adds a source-hash check before execution. Its launcher-inclusive median measured 10.55 ms with 10.78 MiB peak RSS; the table records the earlier migration baseline. See [SECURITY-REVIEW.md](SECURITY-REVIEW.md) for the newer audit. Release settings use size optimization, LTO, one codegen unit, symbol stripping, and abort-on-panic. `ldd` verified dynamic linking to the installed libcurl; Jiff reads the system timezone database without embedding a database. No Rust async runtime or persistent helper is used. Network requests use libcurl directly, avoiding a curl subprocess.

These measurements cover the helper and its shell launcher, not total Quickshell memory, cold network latency, or mpv playback. They exclude the compiler and Cargo cache. RSS includes touched shared libraries. A Python-parent benchmark initially overstated native memory; the C-parent measurement avoids that inherited peak. The results are local samples, not a general performance guarantee.

The existing architecture avoids frequent process startup: one singleton serves all monitors, the helper exits after work, closed-panel checks run at minute/prayer boundaries, and the panel unloads when closed. Seconds are used only for an open countdown or the explicit seconds-in-bar format.

## Code quality and migration

Responsibilities remain separated: `Model.js` contains pure selection/formatting logic; `PrayerState.qml` owns process and timer lifecycle; QML components render the interface. Rust modules separate typed settings/CLI, bounded HTTPS transport, cache/locking, schedule validation, and alerts. Both former Python helpers have been removed.

The JSON protocol consumed by QML is preserved. Schedule output was compared directly against the previous Python implementation using the installed cache; all fields except request timestamps matched. Existing settings, audio, and event-ledger paths remain compatible. The schedule key format retains legacy spacing to reuse existing cache entries where possible.

The Rust suite ports the earlier behavioral checks and adds actual concurrent claims, corrupt-audio recovery, invalid-ledger-entry handling, and failed atomic-write cleanup. Tests use temporary directories and fake network responses. No application-owned unsafe blocks were added. Dependency versions are pinned; builds are explicit, with artifacts outside the live plugin tree and atomic binary installation.

## Verification

- 37 Rust unit tests, a separate real HTTPS integration test (nine assertions), and 39 JavaScript assertions passed.
- `cargo fmt --check` and strict Clippy passed. All QML files parsed; Omarchy manifest validation and Git whitespace checks passed.
- Live shell integration passed with the Rust binary: six timetable rows, a loaded panel, muted adhan playback, working Stop, and no Awqat runtime errors.
- Real cached adhan decoding succeeded with restricted player options. A local playlist disguised as MP3 was rejected.
- Tracked history was scanned for common GitHub/cloud token and private-key patterns; no matches were found.

The changes do not claim exactly-once alert delivery, immunity to provider outages, or universal timezone/high-latitude correctness. A real prayer boundary, multi-day suspend/resume soak test, every theme, and multiple physical monitors were not exercised in this review. Wall-clock measurements are small local samples, not a general performance benchmark.
