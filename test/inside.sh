#!/bin/bash

# The container half of test/run.sh: one full pass per output scale (2x and
# 1x by default, HARNESS_SCALES to change), then contact sheets of the bar
# states, the transition frames and the panel into /shots when it is mounted.

set -u
fail=0

# The QML runs from the folder the manifest names, as Omarchy runs it, and
# that folder must be named for its content (tools/rehash).
entry=$(jq -r '.entryPoints.barWidget' /plugin/manifest.json)
export PLUGIN_QML=${entry%/*}
if bash /plugin/tools/rehash --check; then echo "PASS the QML folder is named for its content"
else echo "FAIL the QML folder is named for its content"; fail=1; fi

expect() {
  if grep -qxF -- "$2" "$1"; then echo "PASS $1: $2"; else echo "FAIL $1: $2"; fail=1; fi
}

run_pass() {
  local scale=$1
  echo "=== pass at ${scale}x"
  rm -rf /tmp/qsroot /tmp/plugins /tmp/scenario /tmp/log /tmp/out /tmp/home
  mkdir -p /tmp/qsroot /tmp/plugins /tmp/scenario /tmp/log /tmp/out/frames /tmp/run /tmp/home/.local/share
  # Corgi installs to ~/.local/share/corgi, outside the plugin folder.
  export HOME=/tmp/home
  cp -r /omarchy/shell/Commons /omarchy/shell/Ui /tmp/qsroot/
  cp /plugin/test/shell.qml /tmp/qsroot/
  cp -r /plugin /tmp/plugins/corgi.computer
  printf '#!/bin/sh\necho fake installer\n' >/tmp/plugins/corgi.computer/install.sh
  install -m 755 /plugin/test/fake/omarchy-launch-terminal /plugin/test/fake/omarchy-launch-browser /plugin/test/fake/hyprctl /usr/local/bin/

  : >/tmp/scenario/feed.jsonl
  cp /plugin/test/usage.json /tmp/scenario/usage.json
  # A second, real `corgi usage --json` to see real density, when mounted
  # (it holds a user's accounts, so it never lives in the repo).
  [[ ! -f /extra/usage-real.json ]] || cp /extra/usage-real.json /tmp/scenario/usage-real.json

  export XDG_RUNTIME_DIR=/tmp/run
  chmod 700 /tmp/run
  rm -f /tmp/run/wayland-*
  cp /usr/sbin/sway /tmp/sway-nocap # drops the file capabilities a container may not grant
  cat >/tmp/sway.conf <<CONF
output HEADLESS-1 resolution $((1200 * scale))x$((1000 * scale)) scale $scale
default_floating_border none
for_window [title="harness-bar"] floating enable, move position 10 10
for_window [title="harness-vbar"] floating enable, move position 10 60
for_window [title="harness-card"] floating enable, move position 200 10
CONF
  WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman \
    /tmp/sway-nocap -c /tmp/sway.conf </dev/null >/tmp/out/sway.log 2>&1 &
  local sway_pid=$!
  WAYLAND_DISPLAY=
  for _ in $(seq 50); do
    for socket in /tmp/run/wayland-*; do
      [[ -S $socket ]] && WAYLAND_DISPLAY=${socket##*/}
    done
    [[ -n $WAYLAND_DISPLAY ]] && break
    sleep 0.1
  done
  export WAYLAND_DISPLAY QT_QPA_PLATFORM=wayland HARNESS_SCALE=$scale
  [[ -z ${HARNESS_RENDER_LOOP:-} ]] || export QSG_RENDER_LOOP=$HARNESS_RENDER_LOOP

  timeout 120 quickshell -p /tmp/qsroot/shell.qml >/tmp/out/qs.log 2>&1
  local status=$?
  kill "$sway_pid" 2>/dev/null

  sed -E 's/\x1b\[[0-9;]*m//g' /tmp/out/qs.log | grep -E "qml:|WARN scene|ERROR|Binding loop|binding loop"
  echo "--- launch.log"; cat /tmp/log/launch.log 2>/dev/null
  echo "--- corgi.log"; grep -v '^watch' /tmp/log/corgi.log 2>/dev/null
  echo "--- hyprctl.log"; cat /tmp/log/hyprctl.log 2>/dev/null

  expect /tmp/log/launch.log "launch [env] [CORGI_INSTALL_PLUGIN=/tmp/plugins/corgi.computer] [CORGI_INSTALL_START=1] [bash] [/tmp/plugins/corgi.computer/install.sh]"
  expect /tmp/log/launch.log "launch [/tmp/home/.local/share/corgi/releases/R1/corgi]"
  expect /tmp/log/launch.log "launch [/tmp/home/.local/share/corgi/releases/R2/corgi]"
  expect /tmp/log/corgi.log "focus 22 --viewer 1"
  expect /tmp/log/corgi.log "workspace switch 1 --viewer 1"
  expect /tmp/log/corgi.log "action new-agent --viewer 1"
  expect /tmp/log/hyprctl.log 'dispatch hl.dsp.focus({ window = "address:0xc0991" })'
  expect /tmp/log/browser.log 'browser [http://localhost:3000/?q=a&b=two]'
  [[ $(grep -c 'CORGI_INSTALL_PLUGIN=/tmp/plugins/corgi.computer' /tmp/log/launch.log) == 2 ]] || { echo "FAIL expected one automatic installer and one click retry"; fail=1; }
  [[ $(grep -c '^focus [0-9]' /tmp/log/corgi.log) == 1 ]] || { echo "FAIL a headless agent was focused by pane"; fail=1; }
  # Six raises: two with no viewer window, which open Corgi, and four that
  # find one and focus its window.
  [[ $(grep -c '^list --json$' /tmp/log/corgi.log) == 6 ]] || { echo "FAIL expected six raises"; fail=1; }
  [[ $(grep -c '^dispatch ' /tmp/log/hyprctl.log 2>/dev/null) == 4 ]] || { echo "FAIL expected four windows focused"; fail=1; }
  [[ $(grep -c '^launch \[/tmp/home/.local/share/corgi/releases/' /tmp/log/launch.log) == 2 ]] || { echo "FAIL Corgi opened other than when no viewer had a window"; fail=1; }
  if pgrep -f "corgi-install-watch" >/dev/null || pgrep -x inotifywait >/dev/null; then
    echo "FAIL the install watch outlived the shell"; fail=1
  fi
  if pgrep -f "tail -n 1 -F" >/dev/null; then echo "FAIL a watch outlived the shell"; fail=1; fi
  if sed -E 's/\x1b\[[0-9;]*m//g' /tmp/out/qs.log | grep -qiE "binding loop|TypeError|ReferenceError"; then
    echo "FAIL QML errors in the log"; fail=1
  fi
  grep -q "failures: 0" /tmp/out/qs.log || fail=1
  [[ $status == 0 ]] || fail=1

  rm -rf "/tmp/pass-$scale"
  cp -r /tmp/out "/tmp/pass-$scale"
}

for scale in ${HARNESS_SCALES:-2 1}; do
  run_pass "$scale"
done

if [[ -d /shots ]] && command -v python3 >/dev/null && python3 -c 'import PIL' 2>/dev/null; then
  # shellcheck disable=SC2086 # one argument per scale
  python3 /plugin/test/sheet.py /shots ${HARNESS_SCALES:-2 1}
fi

echo "result: $([[ $fail == 0 ]] && echo ok || echo FAILED)"
exit "$fail"
