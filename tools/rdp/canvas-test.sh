#!/usr/bin/env bash
# Proves the CDP technique without any remote server: a throwaway headless Brave opens a
# canvas-only page, then a coordinate click and typed keys must arrive as trusted events.
# The live browser and its profile are not touched.
#   canvas-test.sh [--browser PATH] [--dir PATH]
set -euo pipefail

here=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
browser=/opt/brave-origin-bin/brave
out=${XDG_RUNTIME_DIR:-/tmp}/rdp-lab
debug_port=9334
http_port=8766

while (($#)); do
	case $1 in
	--browser) browser=$2 && shift 2 ;;
	--dir) out=$2 && shift 2 ;;
	*)
		printf 'usage: canvas-test.sh [--browser PATH] [--dir PATH]\n' >&2
		exit 2
		;;
	esac
done
for c in "$browser" node python3 curl; do
	command -v "$c" >/dev/null || {
		printf 'canvas-test: missing command: %s\n' "$c" >&2
		exit 1
	}
done
mkdir -p "$out"
profile=$(mktemp -d)
web=0
headless=0
cleanup() {
	((headless)) && kill "$headless" 2>/dev/null || true
	((web)) && kill "$web" 2>/dev/null || true
	wait 2>/dev/null || true
	# The browser can still be writing its cache just after it exits.
	rm -rf -- "$profile" 2>/dev/null || { sleep 1 && rm -rf -- "$profile"; } || true
}
trap cleanup EXIT

python3 -I -m http.server "$http_port" --bind 127.0.0.1 --directory "$here" >/dev/null 2>&1 &
web=$!
# --password-store=basic: over plain SSH, Chromium otherwise waits forever on the desktop
# keyring for its cookie key, and every navigation stalls before reaching the network.
"$browser" --headless --user-data-dir="$profile" --remote-debugging-port="$debug_port" \
	--no-first-run --no-sandbox --disable-gpu --password-store=basic --window-size=900,500 \
	about:blank >/dev/null 2>&1 &
headless=$!
for _ in {1..50}; do
	curl -fs "http://127.0.0.1:$debug_port/json/version" >/dev/null 2>&1 && break
	sleep 0.2
done
page=http://127.0.0.1:$http_port/canvas-probe.html
curl -fs -X PUT "http://127.0.0.1:$debug_port/json/new?$page" >/dev/null

# A new tab can start in the background and load slowly, so bring it forward and wait
# for the page's own script instead of trusting a fixed delay.
ready=no
for _ in {1..40}; do
	state=$(timeout 10 node "$here/cdp-tab.mjs" --port "$debug_port" "$page" \
		'[{"op":"front"},{"op":"eval","label":"state","expr":"typeof window.seen"}]' 2>/dev/null || true)
	if [[ $state == *'state: object'* ]]; then
		ready=yes
		break
	fi
	sleep 0.25
done
[[ $ready == yes ]] || {
	printf 'canvas-test: page did not load; last state: %s\n' "$state" >&2
	exit 1
}

result=$(timeout 40 node "$here/cdp-tab.mjs" --port "$debug_port" "$page" "[
  {\"op\":\"click\",\"x\":300,\"y\":200},
  {\"op\":\"type\",\"text\":\"qb1\"},
  {\"op\":\"wait\",\"ms\":200},
  {\"op\":\"eval\",\"label\":\"seen\",\"expr\":\"JSON.stringify({seen:window.seen,domText:document.body.innerText.trim(),elements:document.querySelectorAll('body *').length})\"}
]")
printf '%s\n' "$result"

printf '%s\n' "$result" | sed -n 's/^seen: //p' | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
seen = d["seen"]
clicks = [e for e in seen if e["type"] == "mousedown"]
keys = [e["key"] for e in seen if e["type"] == "keydown"]
ok = (
    len(clicks) == 1 and clicks[0]["x"] == 300 and clicks[0]["y"] == 200
    and keys == ["q", "b", "1"]
    and all(e["trusted"] for e in seen)
    and d["domText"] == ""
)
print("input and empty DOM: " + ("ok" if ok else "WRONG"))
sys.exit(0 if ok else 1)
'

timeout 40 node "$here/cdp-tab.mjs" --port "$debug_port" "$page" \
	"[{\"op\":\"front\"},{\"op\":\"wait\",\"ms\":300},{\"op\":\"shot\",\"file\":\"$out/canvas-test.png\"}]"
echo 'canvas-test PASS'
