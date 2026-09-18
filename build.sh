#!/usr/bin/env bash
set -euo pipefail
plugin_dir=$(cd -- "$(dirname -- "$0")" && pwd)
for tool in cargo cc pkg-config; do
  command -v "$tool" >/dev/null || {
    echo "Missing build dependency: $tool. See README.md for prerequisites." >&2
    echo 'Awqat does not install system packages. Prepare the dependencies separately, then rerun ./build.sh.' >&2
    exit 1
  }
done
pkg-config --exists libcurl || { echo 'System libcurl development files are required.' >&2; exit 1; }
source_checksums=$(cd "$plugin_dir" && sha256sum Cargo.toml Cargo.lock src/*.rs)
# Keep build churn outside the live plugin tree and discard temporary artifacts.
if [[ -n ${CARGO_TARGET_DIR:-} ]]; then
  build_dir=$CARGO_TARGET_DIR
else
  build_dir=$(mktemp -d "${TMPDIR:-/tmp}/awqat-build.XXXXXX")
  trap 'rm -rf -- "$build_dir"' EXIT
fi
cargo build --manifest-path "$plugin_dir/Cargo.toml" --locked --release --target-dir "$build_dir" "$@"
[[ "$source_checksums" == "$(cd "$plugin_dir" && sha256sum Cargo.toml Cargo.lock src/*.rs)" ]] || {
  echo 'Source changed during compilation. Run build.sh again.' >&2; exit 1;
}
mkdir -p "$plugin_dir/bin"
staged=$(mktemp "$plugin_dir/bin/.awqat-core.XXXXXX")
install -m 755 "$build_dir/release/awqat-core" "$staged"
mv -fT -- "$staged" "$plugin_dir/bin/awqat-core"
staged=$(mktemp "$plugin_dir/bin/.awqat-sources.XXXXXX")
printf '%s\n' "$source_checksums" > "$staged"
mv -fT -- "$staged" "$plugin_dir/bin/source-checksums"
echo "Built Awqat helper: $plugin_dir/bin/awqat-core"
