# Awqat UI/UX audit

Reviewed on the installed Omarchy desktop on 18 September 2026. This records implemented improvements and verification, rather than claiming universal usability across untested systems.

| Area | Finding and implemented change | Verification |
| --- | --- | --- |
| Size and hierarchy | Reduced main panel content width from 400 to 300 logical units, rows from 43 to 30, and countdown card from 166 to 78. Removed the decorative banner and heavy accent outline. | Live screenshot at the user’s display scale. |
| Identity | Replaced the generic crescent and an initially too-solid prototype with an open circular clock mark. Theme-aware vector rendering stays legible in the bar and header. | Bar, header and preview inspected in the running shell. |
| Prayer scanability | English/Arabic names and aligned times; next prayer has a restrained accent. Sunrise never becomes the next prayer. Past entries remain readable and a stale schedule is labeled explicitly. | Live schedule plus next-prayer and rollover tests. |
| Settings organization | Location, Bar, and Alerts tabs separate independent tasks while preserving in-panel drafts until Save. | All three tabs inspected. |
| Format discovery | Each preset has a label and a separate live example, avoiding truncation from combining both on one line. An additional preview uses the actual vector icon. | Menu opened using Enter; visible examples inspected. |
| Custom input | Tokens are documented in place; unknown/unclosed tokens produce feedback and disable Save. Empty custom audio/city inputs cannot be saved. | Automated valid/invalid-format checks and QML syntax/runtime checks. |
| Keyboard | Tab-focusable buttons and format picker, Enter/Space selection, arrows and Home/End navigation, Escape dismissal, and arrow-key volume adjustment. Focus indicators and accessible names were added to key custom controls. | Keyboard-opened picker verified on desktop. Full screen-reader validation was not performed. |
| Smaller displays | Panel dimensions fit available screen bounds; content and format menus scroll with scrollbar affordances. | Implemented using native fitted dimensions/Flickable; very small screens and alternate monitor layouts were not physically tested. |
| Location trust | Automatic/manual badge, explicit refresh state, timezone and calculation method, IP/VPN explanation, and manual override. Country-qualified manual searches are supported. | Live IP detection resolved Riyadh; backend location validation tests. |
| Recovery | Offline and stale-location messages, visible Retry action, partial tomorrow failure handling, damaged-cache recovery, and backoff. Audio failures are visible outside settings too. | Automated offline, corruption, full-cache and partial-failure scenarios. |
| Alert control | Notifications and sound are independent. Test notification, audio preview, volume and stop controls are explicit; full adhan is cached for offline playback. | Notification subprocess tests; real cached adhan decoded and played at zero volume, then stopped. |
| Alert reliability | Only five prayers qualify. Late wake-ups stay silent, and persisted claims prevent duplicate delivery. Playback remains independent of panel visibility. | Duplicate/future/sunrise/late-event tests and live playback state checks. A real prayer-time boundary was not waited for. |
| Footprint | One shared updater; lazily created UI; bounded disk cache; no persistent Python or audio process while idle. | Closed-panel status confirmed `panelLoaded: false`, `openPanels: 0`; warm helper timed separately. |

## Remaining practical limits

- IP location is approximate and may follow a VPN or carrier gateway. Use the visible detected location and manual override when needed.
- Adhan start times are calculated prayer times, not local mosque iqamah times. Hijri dates can differ with local moon sightings.
- Alerts cannot run while the device is asleep or the shell is stopped. System notification suppression still applies.
- The two included adhan choices are general recordings. A local custom file may be used for a preferred recitation.
- Light themes, screen readers, and multiple physical monitors have not been exhaustively tested. Shared-state logic, fitted panel bounds and theme colors are used to support them.
