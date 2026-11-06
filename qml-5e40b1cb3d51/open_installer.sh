#!/bin/bash
# Opens the shared installer once per plugin checkout, or again on a click.
set -euo pipefail
plugin=${1:?plugin directory required}
marker=

if [[ ${2:-} == --once ]]; then
  [[ ! -f "$HOME/.local/share/corgi/current" ]] || exit 0
  [[ -f "$plugin/manifest.json" && -f "$plugin/install.sh" ]] || exit 0
  state=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/corgi.computer
  # Updates keep the checkout; removing and adding it creates a new one.
  identity=$(stat -Lc '%d:%i:%w' "$plugin" | sha256sum | cut -c1-16)
  marker=$state/install-$identity
  mkdir -p "$state"
  mkdir "$marker" 2>/dev/null || exit 0
fi

if ! omarchy-launch-terminal env "CORGI_INSTALL_PLUGIN=$plugin" CORGI_INSTALL_START=1 \
  bash "$plugin/install.sh"; then
  [[ -z $marker ]] || rmdir "$marker"
  exit 1
fi
