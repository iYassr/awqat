# Security and privacy

## Scope

Reviewed on 18 September 2026: all plugin source, subprocess arguments, API responses, local cache and alert state, QML text rendering, audio downloads/playback, IPC, and tracked Git history. This was a source review with targeted adversarial tests and local runtime checks, not an independent penetration test or a guarantee of security.

Awqat runs with the desktop user's permissions inside Omarchy. It has no server, listening network port, credentials, elevated privileges, telemetry service, Python package dependencies, or install hooks. The local shell IPC is available to processes in the same desktop session; it can reveal the detected city/schedule and trigger refresh, notification tests, or audio previews. It is not an authentication boundary against software already running as that user.

## Findings addressed

| Priority | Finding | Change and verification |
| --- | --- | --- |
| Medium | JSON transfers had time limits but no size limit, and followed redirects. | Enforce HTTPS, reject redirects, cap JSON at 256 KiB and audio at 8 MiB. Disable automatic curl configuration with `-q` as the first argument. Tests cover oversized/non-object responses and transport arguments; live prayer and location requests succeeded. |
| Medium | Some QML labels used automatic text detection for API/error/custom input. | All panel text uses explicit plain text, including city, method, Hijri date, and errors. Bar and format previews already used plain text. Notification bodies are HTML-escaped and subprocess arguments remain literal. |
| Medium | Audio could follow embedded references or load adjacent files. | Disable reference traversal, adjacent-file loading, user scripts, configuration, and yt-dlp. Restrict FFmpeg protocols to local files. A cached adhan decoded successfully; a playlist disguised as an MP3 failed to load. |
| Low | Directory permissions depended on the process umask. | Cache and state directories are restricted to mode 0700 when used for writing/locking. Atomic data files use private temporary files (0600). Tests verify directory and file modes. |
| Low | Malformed persisted state could disrupt updates or block alert delivery. | Reject oversized/nested/future-dated cache data, bound the alert ledger, validate text and prayer ordering, and add a three-second alert-lock deadline. Regression tests exercise recovery. |

External values never become shell command strings: helpers and players use argument arrays, query parameters are URL-encoded, and notification/media operands follow `--`. Remote responses cannot select executable paths or download destinations. Built-in audio URLs are fixed; custom audio requires a local regular file with a supported extension.

## Data leaving the machine

| Service | When used | Information available to the service |
| --- | --- | --- |
| ipwho.is | Automatic location; normally every 30 minutes | Public connection IP; the response provides an approximate city and coordinates. |
| Open-Meteo geocoding | Manual city lookup | Entered city query and connection IP. |
| AlAdhan prayer API | Uncached schedule dates or forced refresh | Coordinates, timezone, calculation method, Asr setting, requested date, and connection IP. |
| AlAdhan audio CDN | First selection/preview of an uncached built-in adhan | Requested recording and connection IP. |

The plugin does not persist IP/ISP fields from the location response. It does persist city, coordinates, timezone, prayer schedules, and a small prayer-delivery ledger. Settings, including a selected local audio path, live in Omarchy's `shell.json`. Disabling or removing the plugin does not automatically delete those separate cache/state files. See the README for their locations.

## Remaining boundaries

- TLS protects transport, but prayer accuracy and downloaded recordings still depend on the named providers. Audio header checks are sanity checks, not cryptographic authenticity checks.
- Media is decoded by system mpv/FFmpeg. Playback restrictions reduce exposed features but do not sandbox decoder vulnerabilities; keep Omarchy and its packages updated and select trusted local audio.
- `curl` 8.4+ is required so the transfer cap also applies when a server omits Content-Length. Fixed endpoints reject redirects; a future provider URL change may require an update.
- The user account, its environment/PATH, installed shell/plugins, and plugin/cache directories are trusted. This plugin does not defend against root or malicious code already running as the same user. Existing user-supplied symlinks are not a security boundary.
- Alerts are claimed before delivery to prevent repeats. A crash, notification failure, or unavailable audio after the claim can lose that alert. It is not a guaranteed delivery service.
- No critical or high-severity issue was identified in this review. The secret-pattern scan found no common credential/private-key patterns in tracked history; pattern scanning is not exhaustive.

For a potential vulnerability, avoid posting credentials or a working exploit in a public issue. Use GitHub's private vulnerability reporting if enabled; otherwise open a minimal issue asking for a private reporting channel without sensitive details.

## References

- [curl options and transfer-size behavior](https://curl.se/docs/manpage.html)
- [mpv playback and reference controls](https://mpv.io/manual/stable/)
- [Qt Quick Text formats](https://doc.qt.io/qt-6/qml-qtquick-text.html#textFormat-prop)
