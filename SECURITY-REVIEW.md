# Rust security and size review — 1.2.1

Date: 18 September 2026. Reviewed the complete source, Cargo dependency graph, QML/IPC boundary, shell launcher/build scripts, installed ARM64 executable, caches, and Git history. This is a source review plus targeted tests, not a security certification, a complete system-package audit, or a fuzzing campaign.

## Findings and fixes

| Priority | Finding and precondition | Evidence and fix |
| --- | --- | --- |
| Low | A named pipe in the local audio or JSON cache can block the helper before its file-type check. Requires local cache modification; normal remote responses cannot create pipes. | Reproduced with a temporary `chime.wav` FIFO and the 1.2.0 helper: it exceeded a one-second deadline. Nonblocking, no-follow opens now reject special files; the installed 1.2.1 helper replaced the FIFO with a valid tone and returned promptly. Lock files also require regular files. |
| Low | Directory permissions and cache/lock reads followed leaf symlinks. Requires local filesystem manipulation. | Directory permissions are now set through a directory descriptor opened with `O_DIRECTORY | O_NOFOLLOW`. Data/lock opens reject leaf symlinks. Regression tests prove that an external target's permissions and contents remain unchanged. Optional-cache fallback is restricted to permission, read-only, and storage-full errors rather than swallowing all filesystem errors. |
| Medium (update hardening) | Updating source could leave an old compiled helper running, delaying security fixes until the user remembered to build. No standalone remote exploit was demonstrated. | `build.sh` records source hashes, refuses a source change during compilation, and atomically installs the result and hash list. The launcher refuses missing/stale builds. A copied-install test accepted the current build and rejected a modified Rust source. This is stale-build detection, not a signature or protection against malicious same-user code. |

No critical or high-severity application issue was identified within this review's scope. The fixes do not create a security boundary against root or malicious software running as the desktop user. Ancestor data directories, PATH/environment, installed packages, and installed plugin code remain trusted.

## Boundary checks

- **HTTPS:** actual libcurl transfers against an isolated, temporary TLS server passed nine assertions: valid TLS, exact-size response, declared oversized response, oversized chunked response without Content-Length, redirect rejection, HTTP error rejection, timeout, untrusted certificate rejection, and hostname mismatch rejection. The server independently confirmed the redirect target was never contacted. Production code has no fixture certificate override.
- **Resource limits:** 256 KiB JSON and 8 MiB audio are bounded in the write callback before copying bytes. Requests have connection and overall deadlines. JSON parsing retains Serde's nesting limit. Cache reads are bounded even if a file grows after opening.
- **File writes:** temporary files are private and atomically renamed. Cache/state directories are private. Cleanup is restricted to this application's named cache files. Tests cover failed replacement, corrupt/deep JSON, future timestamps, and duplicate/concurrent claims.
- **Injection:** no shell evaluation of locations, JSON, formats, or audio paths. Query values are encoded; processes use argv arrays. Dynamic UI text is plain text. Notification bodies are escaped. The icon's color property is typed and the SVG data URL is encoded.
- **Audio:** only fixed HTTPS URLs or a user-selected local file are supported. Playback disables configuration, user scripts, adjacent files, references, yt-dlp, and terminal output; FFmpeg protocols are restricted to local files. Earlier normal-media and disguised-playlist checks remain applicable because playback options are unchanged.
- **IPC/privacy:** IPC is local to the desktop session but not authenticated against same-user processes. It exposes the detected location/schedule and playback/test actions. There is no network listener. Provider data disclosures and persisted location/audio-path details are listed in [SECURITY.md](SECURITY.md).
- **Binary hardening:** `readelf` confirmed PIE, non-executable stack, GNU RELRO, and immediate relocation (`BIND_NOW`). Application Rust contains no `unsafe` blocks; native dependencies still have their own unsafe/FFI code.
- **Secrets:** scanned all four pre-review Git commits for common GitHub/cloud token and private-key patterns; no matches. This is a targeted pattern scan, not proof that every possible secret format is absent.

## Dependency check and limits

All **55 locked crates.io package/version entries** were queried against OSV, with **zero returned advisories** at review time. The locked versions did not change when libc became a direct dependency. [dependency-audit.json](dependency-audit.json) records the request package set and returned results. [RustSec](https://rustsec.org/) exports its advisory data to OSV. This point-in-time check cannot detect unpublished vulnerabilities or guarantee future safety.

The runtime is dynamically linked to system libraries, so Cargo advisories alone do not cover everything:

| Installed component | Review result |
| --- | --- |
| libcurl 8.22.0 | The current upstream advisory list's newest affected ranges end at 8.21.0. TLS/redirect/size behavior was also tested directly. [curl advisories](https://curl.se/docs/security.html) |
| OpenSSL 3.6.4 | Matches the fixed 3.6-series version listed in the newest reviewed upstream advisories. [OpenSSL advisories](https://openssl-library.org/news/vulnerabilities/) |
| mpv 0.41.0 | The published terminal-injection advisory lists versions below 0.41.0. Awqat also disables terminal output. This is not a complete audit of mpv. [mpv advisory](https://github.com/mpv-player/mpv/security/advisories/GHSA-546v-22c3-7927) |
| FFmpeg 9.0.1 | The upstream security page did not provide a matching 9.0 release section, so this review does not claim complete vulnerability clearance for the installed decoder. [FFmpeg security](https://ffmpeg.org/security.html) |

Media decoding is not sandboxed. Codec vulnerabilities, provider compromise, wrong-but-well-formed prayer data, OS package issues, and same-user attacks remain outside the guarantees of this plugin. Keep system packages updated and select trusted custom media. Alert delivery remains at-most-once and can be lost after a claim if the process or output fails.

## Size and startup audit

| Component | Measured size |
| --- | --- |
| Previous 1.2.0 ARM64 executable | 782,384 bytes (764 KiB) |
| Hardened 1.2.1 executable | 741,072 bytes (724 KiB) |
| Reduction | 41,312 bytes, 5.3% |
| Installed checkout, including executable and Git history | Approximately 1.4 MiB at review time |
| Existing cache on this machine | Approximately 3.5 MiB, mostly one downloaded adhan |

The smaller build changes release optimization from `s` to `z`, keeping LTO, stripping, one codegen unit, and panic-abort. It preserves the dynamic system libcurl and system timezone database. Safety checks, TLS, and file validation were retained.

A C `fork/exec` + `wait4` harness measured **10.55 ms median** over 15 warm launcher invocations and **10.78 MiB maximum child RSS**. Source hashing adds a few milliseconds compared with the earlier approximately 8 ms launcher path; this cost prevents stale security updates. The native binary alone measured 5.47 ms in a separate run. These samples exclude cold transfers, the shell, and playback, and are not a claim of universal performance.

Audio is optional and downloaded once. JSON remains capped at 2 MiB/96 files/35 days; two optional built-in recordings are capped at 8 MiB each. User-owned custom audio is not copied into this cache. Rust/Cargo, dependency caches, and temporary compiler artifacts are build-time storage, not the runtime binary; do not confuse an installed compiler's size with the plugin's size. Review build artifacts are cleaned after verification.

## Reproduction

```sh
cargo test --locked --target-dir /tmp/awqat-security-build
cargo clippy --locked --target-dir /tmp/awqat-security-build --all-targets -- -D warnings
cargo fmt --check
node tests/model.test.cjs
python3 tests/security_transport.py
omarchy plugin validate .
```

The optional transport fixture requires Python 3, OpenSSL, and permission to bind localhost. It creates a temporary certificate and server solely for the test; Python is not a runtime dependency. The standard Rust suite has 37 passing tests; its extra HTTPS test is marked ignored until run through that fixture. A further 39 JavaScript assertions cover bar formatting and scheduling. Shell syntax, source-hash checks, and live helper state were also checked.
