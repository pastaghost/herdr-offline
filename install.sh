#!/bin/sh
# Installs the Herdr desktop app and herdr-core (hc) on an Apple Silicon Mac
# from the files in this repo. No network.
#
#   ./install.sh               # app + core
#   ./install.sh --app-only
#   ./install.sh --core-only
#
# Follows https://releases.herdr.dev/app/install.sh and .../core/install.sh:
# Herdr.app goes to ~/Applications (signature untouched), `herdr-app` and
# herdr-core/`hc` to ~/.local/bin (HC_INSTALL_DIR changes the core's folder).
# An existing core is updated in place so running terminals keep running;
# behind a VPN the app can't update the core itself, so this does it.
set -eu

repo=$(cd "$(dirname "$0")" && pwd)
bin="$HOME/.local/bin"
core_bin=${HC_INSTALL_DIR:-$bin}
team=2W9652Q7QR

do_app=1
do_core=1
for a in "$@"; do
  case $a in
    --app-only) do_core=0 ;;
    --core-only) do_app=0 ;;
    -h | --help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "install: unknown option $a" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
fail() { say "install: $*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || fail "this repo only has the macOS build"
case "$(uname -m)" in
  arm64) ;;
  x86_64)
    # Rosetta reports x86_64 on Apple Silicon too.
    [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ] ||
      fail "the Herdr app has no Intel Mac build" ;;
  *) fail "no build for $(uname -m)" ;;
esac
[ "$(id -u)" != 0 ] || fail "run this as your normal user, not with sudo"

# lookup KIND -> $version, $file (checksum verified)
lookup() {
  line=$(awk -v k="$1" '$1 == k' "$repo/versions.txt")
  [ -n "$line" ] || fail "no $1 in versions.txt"
  version=$(printf '%s' "$line" | awk '{print $2}')
  rel=$(printf '%s' "$line" | awk '{print $3}')
  file=$repo/$rel
  [ -f "$file" ] || fail "missing $rel (incomplete clone?)"
  want=$(awk -v p="$rel" '$2 == p {print $1}' "$repo/SHA256SUMS")
  [ "$(shasum -a 256 "$file" | cut -d' ' -f1)" = "$want" ] || fail "$rel is damaged (checksum mismatch)"
}

# newer OLD NEW: exit 0 if NEW > OLD, 1 if NEW < OLD, 2 if equal ("hc " prefix ok)
newer() {
  awk -v old="$1" -v new="$2" 'BEGIN {
    sub(/^hc /, "", old); sub(/^hc /, "", new)
    split(old, a, /[.-]/); split(new, b, /[.-]/)
    for (i=1; i<=3; i++) { if (a[i]+0 > b[i]+0) exit 1; if (a[i]+0 < b[i]+0) exit 0 }
    exit 2
  }'
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$bin"

# ------------------------------------------------------------------ app
if [ "$do_app" = 1 ]; then
  lookup app
  mkdir -p "$tmp/app"
  tar -xzf "$file" -C "$tmp/app"
  new="$tmp/app/Herdr.app"
  [ -d "$new" ] || fail "the archive holds no Herdr.app"
  # Must be Herdr's own Developer ID signature, intact.
  /usr/bin/codesign --verify --deep --strict \
    -R "=identifier \"dev.herdr.app\" and anchor apple generic and certificate leaf[subject.OU] = \"$team\"" "$new" \
    || fail "Herdr.app is not a valid signed Herdr release"
  apps="$HOME/Applications"
  app="$apps/Herdr.app"
  if pgrep -qf "$app/Contents/MacOS/Herdr"; then
    say "install: Herdr is running from $app; quit it first, then run this again." >&2
    exit 1
  fi
  mkdir -p "$apps"
  rm -rf "$app"
  mv "$new" "$app"
  ln -sfn "$app/Contents/MacOS/Herdr" "$bin/herdr-app"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app" 2>/dev/null || true
  say "Herdr app $version installed in $app"
  [ ! -d /Applications/Herdr.app ] || say "  Note: an older copy is also in /Applications/Herdr.app; you can delete it."
fi

# ----------------------------------------------------------------- core
if [ "$do_core" = 1 ]; then
  lookup core
  mkdir -p "$tmp/core"
  tar -xzf "$file" -C "$tmp/core"
  bundled="$tmp/core/Herdr Core.app/Contents/MacOS/herdr-core"
  [ -x "$bundled" ] || fail "the archive holds no Herdr Core.app"
  /usr/bin/codesign --verify --strict \
    -R "=identifier \"dev.herdr.core\" and anchor apple generic and certificate leaf[subject.OU] = \"$team\"" "$tmp/core/Herdr Core.app" \
    || fail "Herdr Core.app is not a signed Herdr release"
  candidate=$("$bundled" --version)

  existing=""
  if [ -x "$core_bin/herdr-core" ]; then existing="$core_bin/herdr-core"
  elif command -v herdr-core >/dev/null 2>&1; then existing=$(command -v herdr-core); fi

  if [ -n "$existing" ] && [ "$existing" != "$core_bin/herdr-core" ]; then
    say "herdr-core already installed at $existing (not managed here); left alone."
  elif [ -n "$existing" ]; then
    installed=$("$existing" --version)
    set +e; newer "$installed" "$candidate"; cmp=$?; set -e
    case $cmp in
      2) say "herdr-core already at ${installed#hc }; nothing to do." ;;
      1) say "herdr-core ${installed#hc } is newer than the bundled ${candidate#hc }; left alone." ;;
      0)
        "$bundled" --hc-install-bundle "$bundled" "$core_bin/herdr-core" || fail "installing Herdr Core.app failed"
        "$core_bin/herdr-core" server restart >/dev/null || fail "restarting the core failed"
        say "herdr-core updated to $version (running terminals kept)." ;;
    esac
  else
    mkdir -p "$core_bin"
    "$bundled" --hc-install-bundle "$bundled" "$core_bin/herdr-core" || fail "installing Herdr Core.app failed"
    say "herdr-core $version installed in $core_bin/herdr-core"
  fi
  if ! command -v hc >/dev/null 2>&1 && [ ! -e "$core_bin/hc" ] && [ -x "$core_bin/herdr-core" ]; then
    ln -s herdr-core "$core_bin/hc"
  fi
fi

case ":$PATH:" in
  *":$bin:"*) ;;
  *) say "Add $bin to your PATH to use herdr-app and hc from a terminal:"
     say "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc" ;;
esac
[ "$do_app" = 0 ] || say "Open Herdr from ~/Applications (or Spotlight), or run: herdr-app"
