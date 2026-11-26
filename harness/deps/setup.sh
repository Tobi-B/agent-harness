#!/usr/bin/env bash
# Fetch the tools the harness runs on into harness/deps/ — pinned, checked, and
# nowhere else on the machine (meta-0011).
#
#   bash harness/deps/setup.sh              # fetch what is missing or differs
#   bash harness/deps/setup.sh --check      # pure: exit 1 if anything is missing or differs
#   bash harness/deps/setup.sh --hash FILE  # print FILE's checksum (to bump deps.lock)
#
# deps.lock names, for every tool and platform, the URL and the SHA-256 the
# download must have. A file that does not match is never installed. The gates
# use only what lands in bin/ — a system-wide yq or jq does not count. bin/ and
# vendor/ stay out of git.
#
#   HARNESS_DEPS_MIRROR=URL        fetch <URL>/<file name> instead of the URL in
#                                  deps.lock (a proxy, an offline mirror)
#   HARNESS_DEPS_PLATFORM=os-arch  use this platform instead of the detected one
#
# Kept to bash 3.2: it has to run before anything else is in place.
set -euo pipefail

DEPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK="$DEPS_DIR/deps.lock"
TOOLS="yq jq mermaid"

fail() {
  echo "FAIL: setup: $*" >&2
  exit 1
}

# Read from stdin: GNU sha256sum escapes a file name that holds a backslash,
# and then the line no longer starts with the hash.
checksum_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum < "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 < "$1" | cut -d' ' -f1
  else
    echo "FAIL: setup: need sha256sum or shasum to check downloads" >&2
    exit 2
  fi
}

detect_platform() {
  local os arch
  case "$(uname -s)" in
    Linux)                os=linux ;;
    Darwin)               os=darwin ;;
    MINGW*|MSYS*|CYGWIN*) os=windows ;;
    *)                    os=$(uname -s | tr '[:upper:]' '[:lower:]') ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64)  arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *)             arch=$(uname -m) ;;
  esac
  echo "$os-$arch"
}

# "version dest url checksum" of the line for tool $1 on platform $2 (or "any").
lock_entry() {
  awk -v t="$1" -v p="$2" '
    { sub(/\r$/, "") }
    /^[[:space:]]*(#|$)/ { next }
    $1 == t && ($3 == p || $3 == "any") { print $2, $4, $5, $6; exit }
  ' "$LOCK"
}

platforms_of() {
  awk -v t="$1" '{ sub(/\r$/, "") } $1 == t { printf "%s ", $3 }' "$LOCK"
}

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    echo "FAIL: setup: need curl or wget to download" >&2
    exit 2
  fi
}

mode=install
case "${1:-}" in
  --check) mode=check ;;
  --hash)
    [ $# -ge 2 ] && [ -f "$2" ] || fail "--hash needs a file"
    checksum_of "$2"
    exit 0
    ;;
  '') ;;
  *) echo "unknown argument: $1 (use --check, --hash FILE, or nothing)" >&2; exit 2 ;;
esac

[ -f "$LOCK" ] || fail "missing $LOCK"
platform="${HARNESS_DEPS_PLATFORM:-$(detect_platform)}"
problems=0

for tool in $TOOLS; do
  entry=$(lock_entry "$tool" "$platform")
  [ -n "$entry" ] \
    || fail "no pinned $tool for platform '$platform' in deps.lock (pinned for: $(platforms_of "$tool"))"
  read -r version dest url sum <<< "$entry"
  target="$DEPS_DIR/$dest"

  have=""
  [ -f "$target" ] && have=$(checksum_of "$target")
  if [ "$have" = "$sum" ]; then
    echo "ok: $tool $version ($dest)"
    continue
  fi

  if [ "$mode" = check ]; then
    if [ -z "$have" ]; then
      echo "MISSING: $tool $version ($dest)" >&2
    else
      echo "DIFFERS: $tool $version ($dest) is not the pinned file" >&2
    fi
    problems=1
    continue
  fi

  src="$url"
  [ -z "${HARNESS_DEPS_MIRROR:-}" ] || src="${HARNESS_DEPS_MIRROR%/}/${url##*/}"
  mkdir -p "$(dirname "$target")"
  part="$target.part"
  rm -f "$part"
  echo "fetching: $tool $version <- $src"
  if ! fetch "$src" "$part"; then
    rm -f "$part"
    fail "could not download $src"
  fi
  got=$(checksum_of "$part")
  if [ "$got" != "$sum" ]; then
    rm -f "$part"
    fail "checksum mismatch for $tool $version from $src: expected $sum, got $got — nothing installed"
  fi
  mv -f "$part" "$target"
  case "$dest" in bin/*) chmod +x "$target" ;; esac
  echo "installed: $tool $version -> harness/deps/$dest"
done

if [ "$mode" = check ]; then
  if [ "$problems" -ne 0 ]; then
    echo "FAIL: setup: pinned tools are missing or differ — run: bash $DEPS_DIR/setup.sh" >&2
    exit 1
  fi
  echo "PASS: pinned tools in place ($platform)"
else
  echo "done: the gates use $DEPS_DIR/bin — nothing was installed outside harness/deps/"
fi
