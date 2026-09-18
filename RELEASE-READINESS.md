# Public release review — 1.2.3

Reviewed on 18 September 2026. Scope: installation, source packaging, QML
lifecycle and settings, Rust transport/storage/alerts, timetable validation,
privacy, dependencies, documentation, and the marketplace submission.

## Findings and resolution

| Priority | Finding | Resolution |
| --- | --- | --- |
| Medium | The shared QML singleton could keep its timer, helper, or audio active after the last widget was removed. | Widgets now attach/detach explicitly. Removing the last consumer stops background work, cancels pending audio, and clears the schedule. A remaining consumer keeps its shared state. Late helper results cannot repopulate disabled state. |
| Low | Enter in the city field could call Save while the Save button was disabled. | The save function and button now share the same validation, covering manual city, custom format, and custom audio path requirements. |
| Low | The latest source release predated the selected icon and later setup documentation. | Version 1.2.3 packages the current icon, setup instructions, and review fixes together. The earlier tag is retained as historical source. |

No additional release-blocking issue was identified in this review. This is
a local source review and targeted test run, not an independent security
certification. Marketplace listing still requires maintainer approval.

## Verification

- A clean copy containing tracked source built successfully without an
  existing helper, from a path containing spaces and an unrelated working
  directory. Before building, the launcher returned its documented setup
  error; afterwards it reported version 1.2.3. The default build removed its
  temporary compilation output.
- 41 Rust unit tests, 39 JavaScript checks, and three isolated CLI tests
  passed. The separate real HTTPS fixture passed all nine transport checks,
  including certificate/hostname rejection, size limits, redirects, and a
  deadline. The redirect destination was never contacted.
- 15 isolated QML lifecycle checks passed against the actual singleton:
  two consumers, last-consumer removal, audio cancellation, queued sound
  changes, ignored late results, schedule-fetch cancellation, disabled
  refresh, and reattachment. Fake helpers keep this test independent of
  network services, desktop notifications, and real playback.
- Strict Clippy, Rust formatting, shell syntax, all QML parsing, the installed
  Omarchy manifest validator, and Git whitespace checks passed.
- After a shell restart, the live panel displayed six timetable rows and a
  next-prayer bar label, with no Awqat schedule/audio error. No Awqat runtime
  error appeared in the inspected shell log. Existing shell portal and
  marketplace-catalog warnings were unrelated to the plugin.
- A fresh OSV query covered all 55 locked registry packages and returned no
  known advisories. The package inventory and response are in
  [dependency-audit.json](dependency-audit.json). This does not audit system
  libcurl, mpv, Qt, or undisclosed vulnerabilities.
- The release helper measured **740,592 bytes (about 724 KiB)** on Linux
  ARM64. It exits after work; compilation output, shared libraries, shell
  memory, cache, and optional audio are excluded. No new runtime dependency
  was added. Earlier timing measurements are in [REVIEW.md](REVIEW.md).

## Release conditions and limits

This is a source release with an explicit build step. Rust/Cargo, a C
toolchain, pkg-config, and libcurl development files must already be
available. There is no automatic package installation or bundled native
binary. The README documents updates, rebuilds, removal, data locations,
optional audio dependencies, and external services.

The build was exercised with Rust 1.98.1 on ARM64. Locked dependencies declare
no requirement newer than the advertised Rust 1.89 minimum, but that older
compiler and x86 hardware were not exercised. Two consumers were tested in
the isolated harness, not on two physical monitors. This pass did not run a
multi-day suspend/resume soak test or wait for an actual prayer boundary.

Prayer times depend on the provider, location, calculation method, and
timezone data. Alerts require an awake device and running shell; missed
prayers beyond the documented grace period are not replayed. The existing
security and privacy boundaries remain in [SECURITY.md](SECURITY.md).
