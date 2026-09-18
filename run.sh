#!/bin/bash
# Builds AnyPlay and starts it. This is the one command.
#
# The app is started with `open`, not directly: only then is the bundle itself the
# responsible process for the permissions. Started from a terminal, Screen Recording
# and Accessibility would be attributed to the terminal instead.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/build.sh"
pkill -x AnyPlay 2>/dev/null || true
sleep 0.5
open "$DIR/build/AnyPlay.app" "$@"
