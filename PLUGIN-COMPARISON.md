# Lessons from other Omarchy plugins

Reviewed 18 September 2026. Sources were read, not installed or executed.
GitHub stars are a discovery signal, not install counts or evidence of quality.
A GitHub API search for `topic:omarchy-plugin`, sorted by stars, surfaced
OmaStorm (111), Radio Atlas (70), and NextHop (56) among the leading results
at the time of review. This is a sample, not an exhaustive popularity ranking.

| Reference | Observed pattern | Decision for Awqat |
| --- | --- | --- |
| [OmaStorm](https://github.com/wesleygrimes/omastorm/blob/aaa297a6b4930a721d1e5cad1243d7886ceb096e/ui/PluginSession.qml) | Shared session across outputs; attempt numbers reject superseded location results. | Keep one shared prayer state. Add generation checks so stopped/superseded audio preparation cannot later play or overwrite an error. |
| [Radio Atlas](https://github.com/AksharP5/omarchy-radio-atlas/blob/b290c29c1a9bfd1a0296f05fe995e1cd4e6e6ccd/BarWidget.qml) | Tracks submitted versus pending volume, queues newer changes, uses native WidgetButton and bounded state parsing. | Keep native controls and bounded Rust input. Queue the latest sound warmup while an older preparation finishes. |
| [NextHop](https://github.com/x3me/omarchy-nexthop/blob/5fdddb4cf0e82f3972aedf593df77400d3f57d00/Service.qml) | Explicit liveness checks, backoff, and version handover for a persistent monitoring daemon. | Keep deadlines, backoff, and source/binary matching. A continuous monitoring daemon is unnecessary for Awqat's infrequent schedule updates. |
| [OmaSettings](https://github.com/twiking/omasettings/blob/main/Service.qml) | Loads settings lazily, remembers a pending page, exposes open/close/show/hide lifecycle routes. | Retain lazy panel loading and pending settings page. Awqat additionally unloads the closed panel. |
| [Scratchpad](https://github.com/nlboris/omarchy-scratchpad/blob/master/Scratchpad.qml) | Derives its small indicator from Hyprland state instead of polling subprocesses. | Retain bindings for visual state and run helpers only for schedule/audio work. |
| [Built-in clock](https://github.com/omacom/omarchy/blob/quattro/shell/plugins/panels/clock/BarWidget.qml) and [weather](https://github.com/omacom/omarchy/blob/quattro/shell/plugins/panels/weather/BarWidget.qml) | Native panel routing and popout handover; the clock only ticks per second for formats that need it. | Awqat already uses those panel contracts and adapts its timer to visible countdown needs. |

The first-party clock/weather source was also inspected in the installed
`/usr/share/omarchy/shell/plugins/panels/` tree. Mutable source links above
may differ after this review; the three popular community examples use
commit-pinned links.

## Changes applied in 1.2.2

- Finish helper responses in one process-exit handler, avoiding competing
  stdout/exit error updates. A timeout keeps its specific message.
- Invalidate old audio completions on Stop, location changes, or sound changes.
  Deferred prayer work checks the generation again before it starts.
- Queue a changed sound for preparation if the old request is still running.
- Move audio-cache validation into audio preparation, after desktop notification
  delivery. An audio storage failure still reports an error, but no longer
  prevents the independent text notification.
- Return typed days from the schedule loader, flatten adjacent-day error
  handling, reuse the timezone object, and remove a guarded cache `unwrap`.
- Reject invalid location modes and next-day schedules mislabeled as today.
  Preserve the existing exception for Isha after midnight.

## Accuracy and verification limits

[AlAdhan's API](https://aladhan.com/prayer-times-api) remains the timetable
provider. Awqat validates dates, timezone-bearing timestamps, ordering, and
settings; it does not independently recompute astronomical prayer times.
IP location is approximate and can reflect a VPN exit location. Manual city
selection and the calculation method should match the user's location and
local practice. High-latitude schedules and every civil-time transition are
not independently certified by these tests.

New regressions exercise a mislabeled next-day response, invalid location
mode, New York's 23-hour spring day and 25-hour autumn day, audio-root symlink
rejection, notification delivery with unusable audio storage, duplicate
suppression after partial delivery, and the correct preview-cache directory.
Audio lifecycle was checked in the live Omarchy shell using muted playback
and Stop; it has not undergone a multi-day suspend/resume soak test.

No dependencies or background services were added. The ARM64 release binary
is 740,656 bytes (about 724 KiB). One local 15-run warm-cache sample measured
8.48 ms median launcher time and 10.78 MiB maximum child RSS. These small
samples do not establish a statistically significant speed improvement.
