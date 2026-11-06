#!/bin/bash

# Runs Widget.qml through its states without an Omarchy desktop: Quickshell on
# headless sway (a real wlr-layer-shell, so the dropdown loads), Omarchy's own
# qs.Commons and qs.Ui, and fakes for corgi, omarchy-launch-terminal and
# omarchy-launch-browser that log what the widget asked of them.
#
#   test/run.sh <omarchy-checkout> [<screenshot-dir>]
#
# Needs Docker. Everything happens in a throwaway archlinux container; the
# plugin and the Omarchy checkout are mounted read-only. Prints PASS/FAIL
# lines and the fakes' logs, and exits non-zero on any failure.

set -eu

omarchy=$(cd "${1:?usage: test/run.sh <omarchy-checkout> [<screenshot-dir>]}" && pwd)
plugin=$(cd "$(dirname "$0")/.." && pwd)
shots=${2:-}
[[ -f $omarchy/shell/Ui/KeyboardPanel.qml ]] || { echo "not an Omarchy checkout: $omarchy" >&2; exit 2; }

mounts=(-v "$omarchy:/omarchy:ro" -v "$plugin:/plugin:ro")
if [[ -n $shots ]]; then
  mkdir -p "$shots"
  mounts+=(-v "$(cd "$shots" && pwd):/shots")
fi

# The packages go into an image once, named for their list, so a run only
# starts a container. A new package list makes a new image.
packages="quickshell qt6-declarative sway jq ttf-jetbrains-mono-nerd python-pillow inotify-tools"
image="corgi-omarchy-harness:$(printf %s "$packages" | sha256sum | cut -c1-12)"
if ! docker image inspect "$image" >/dev/null 2>&1; then
  echo "Building $image (once)…" >&2
  printf 'FROM archlinux:latest\nRUN pacman -Syu --noconfirm %s && pacman -Scc --noconfirm\n' "$packages" |
    docker build -q -t "$image" - >/dev/null
fi

docker run --rm "${mounts[@]}" "$image" bash /plugin/test/inside.sh
