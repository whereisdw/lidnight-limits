#!/bin/bash
# VERSION must be x.y.z, and any concrete version in README install commands (LidnightLimits-x.y.z.zip,
# /download/vx.y.z/) must equal it. The placeholder "x.y.z" is allowed. build.sh must read VERSION, not hard-code it.
set -euo pipefail
cd "$(dirname "$0")/.."
V=$(tr -d '[:space:]' < VERSION)
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION '$V' is not x.y.z"; exit 1; }
bad=0
while read -r found; do
  [ "$found" = "$V" ] || { echo "README mentions version $found, VERSION is $V"; bad=1; }
done < <(grep -oE '(LidnightLimits-|/download/v|--version[ =]v?)[0-9]+\.[0-9]+\.[0-9]+' README.md | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
grep -q 'whereisdw/tap/lidnight-limits' README.md || { echo "README lost the brew cask install command"; bad=1; }
grep -q 'cat VERSION' build.sh || { echo "build.sh no longer reads VERSION"; bad=1; }
[ "$bad" = 0 ] && echo "OK: VERSION $V consistent with README and build.sh"
exit "$bad"
