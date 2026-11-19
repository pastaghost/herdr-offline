#!/bin/sh
# Refreshes the bundled Herdr desktop app and herdr-core for Apple Silicon
# macOS. Run on a machine that CAN reach releases.herdr.dev, then commit and
# push:
#
#   ./fetch.sh
#
# Each file is checked against the SHA-256 in the upstream manifest.
set -eu
cd "$(dirname "$0")"
target=macos-aarch64
releases=https://releases.herdr.dev

need() { command -v "$1" >/dev/null 2>&1 || { echo "fetch: needs $1" >&2; exit 1; }; }
need curl
need python3

sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "$releases/app/latest.json" -o "$tmp/app.json"
curl -fsSL "$releases/core/latest.json" -o "$tmp/core.json"

# "kind version url sha256" for this target from both manifests.
python3 -I - "$tmp/app.json" "$tmp/core.json" "$target" > "$tmp/list" <<'PY'
import json, sys
for kind, path in (("app", sys.argv[1]), ("core", sys.argv[2])):
    m = json.load(open(path))
    t = m["targets"][sys.argv[3]]
    print(kind, m["version"], t["url"], t["sha256"])
PY

rm -rf app core
: > "$tmp/sums"
: > "$tmp/versions"
while read -r kind version url want; do
  name=${url##*/}
  mkdir -p "$kind/$version"
  echo "fetch: $kind $version"
  curl -fsSL --retry 3 "$url" -o "$kind/$version/$name"
  [ "$(sha256 "$kind/$version/$name")" = "$want" ] || { echo "fetch: checksum mismatch for $url" >&2; exit 1; }
  printf '%s  %s\n' "$want" "$kind/$version/$name" >> "$tmp/sums"
  printf '%s %s %s\n' "$kind" "$version" "$kind/$version/$name" >> "$tmp/versions"
done < "$tmp/list"

mv "$tmp/sums" SHA256SUMS
mv "$tmp/versions" versions.txt
cp "$tmp/app.json" app/upstream-latest.json
cp "$tmp/core.json" core/upstream-latest.json
echo "fetch: done. Review with 'git status', then commit and push."
