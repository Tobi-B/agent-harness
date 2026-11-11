#!/usr/bin/env bash
# Package this repo's skills as zips for uploading as account skills.
#
# The account copy used to be edited in place and "adopted" back into the repo
# afterwards, which is how a workflow version went live before its ADR was
# approved. The direction is now one-way: edit here, package, upload. Each zip
# carries a VERSION file naming the workflow version and commit it was built
# from, so a copy that has fallen behind can be recognised.
#
#   bash tools/package-skill.sh            # -> dist/<skill>.zip
#   bash tools/package-skill.sh OUT_DIR    # -> OUT_DIR/<skill>.zip
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$REPO_ROOT/dist}"

[ -d "$REPO_ROOT/skills/harness-init/assets" ] \
  || { echo "FAIL: skill assets missing — run: bash tools/sync-skill.sh" >&2; exit 1; }

# The zip must be built from what is committed and in sync, or its stamp lies.
bash "$REPO_ROOT/tools/sync-skill.sh" --check >/dev/null \
  || { echo "FAIL: skill assets are stale — run: bash tools/sync-skill.sh" >&2; exit 1; }

wf=$(awk '/^version:/ { print $2; exit }' "$REPO_ROOT/harness/workflow.yaml")
sha=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
dirty=""
[ -z "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ] || dirty="-dirty"
stamp="workflow v${wf}, commit ${sha}${dirty}, $(date -u +%Y-%m-%d)"

# A working python: on Windows `python3` can be a Store stub that exits non-zero.
find_python() {
  local p
  for p in python3 python py; do
    if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import zipfile' >/dev/null 2>&1; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

# make_zip DIR NAME: zip the folder DIR/NAME into DIR/NAME.zip, with NAME/ as
# the top-level entry — the layout a skill upload expects.
make_zip() {
  local dir="$1" name="$2" py
  if command -v zip >/dev/null 2>&1; then
    (cd "$dir" && zip -q -r "$name.zip" "$name")
  elif py=$(find_python); then
    (cd "$dir" && "$py" -c 'import shutil, sys; shutil.make_archive(sys.argv[1], "zip", ".", sys.argv[1])' "$name")
  elif command -v powershell.exe >/dev/null 2>&1; then
    echo "WARN: no zip and no python — falling back to PowerShell Compress-Archive" >&2
    (cd "$dir" && powershell.exe -NoProfile -Command \
      "Compress-Archive -Path '$name' -DestinationPath '$name.zip' -Force")
  else
    echo "FAIL: need one of zip, python or powershell.exe to build the archive" >&2
    return 1
  fi
}

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$OUT"

for skill in "$REPO_ROOT"/skills/*/; do
  name="$(basename "$skill")"
  cp -r "$skill" "$stage/$name"
  echo "$stamp" > "$stage/$name/VERSION"
  make_zip "$stage" "$name"
  mv "$stage/$name.zip" "$OUT/$name.zip"
  echo "packaged: $OUT/$name.zip ($stamp)"
done

if [ -n "$dirty" ]; then
  echo "WARN: the working tree has uncommitted changes — commit before uploading, so the stamp names a real commit" >&2
fi
echo "upload each zip as an account skill; do not edit the uploaded copy — change this repo and package again"
