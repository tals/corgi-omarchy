#!/bin/bash

# Brings Corgi forward: the viewer used last whose terminal window Hyprland
# shows does what was asked, and that window takes focus. With no such
# viewer, Corgi opens in a new terminal.
#
#   raise.sh CORGI                     the viewer alone
#   raise.sh CORGI focus PANE          select PANE in it
#   raise.sh CORGI new-tab WORKSPACE   its new-tab picker, in WORKSPACE

set -u
corgi=$1 what=${2:-} id=${3:-}

# Each viewer's ID and process, the one used last first.
viewers=$(timeout 10 "$corgi" list --json 2>/dev/null |
  jq -r '.viewers // [] | sort_by(-(.active // 0)) | .[] | "\(.id) \(.pid // 0)"' 2>/dev/null)
# Each window's process and address, the one focused last first.
windows=$(hyprctl clients -j 2>/dev/null |
  jq -r 'sort_by(.focusHistoryID) | .[] | "\(.pid) \(.address)"' 2>/dev/null)

# The window showing process $1: its own, or its nearest ancestor's, the
# terminal the viewer runs in.
window_of() {
  local pid=$1 hops address
  for ((hops = 0; hops < 32 && pid > 1; hops++)); do
    address=$(awk -v pid="$pid" '$1 == pid { print $2; exit }' <<<"$windows")
    if [[ $address =~ ^0x[0-9a-fA-F]+$ ]]; then
      echo "$address"
      return
    fi
    pid=$(awk '/^PPid:/ { print $2 }' "/proc/$pid/status" 2>/dev/null)
    [[ $pid =~ ^[0-9]+$ ]] || return
  done
}

viewer='' address=''
while read -r v pid; do
  [[ $v =~ ^[1-9][0-9]*$ && $pid =~ ^[0-9]+$ ]] || continue
  address=$(window_of "$pid")
  if [[ -n $address ]]; then
    viewer=$v
    break
  fi
done <<<"$viewers"
[[ -n $viewer ]] || exec omarchy-launch-terminal "$corgi"

case $what in
  focus) timeout 10 "$corgi" focus "$id" --viewer "$viewer" ;;
  new-tab)
    timeout 10 "$corgi" workspace switch "$id" --viewer "$viewer" &&
      timeout 10 "$corgi" action new-agent --viewer "$viewer" ;;
esac >/dev/null

# Hyprland's Lua dispatch, then the older form, as omarchy-hyprland-focus-app does.
hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })" >/dev/null 2>&1 ||
  hyprctl dispatch focuswindow "address:$address" >/dev/null
