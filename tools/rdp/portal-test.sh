#!/usr/bin/env bash
# Clipboard tests against a signed-in TSPlus HTML5 tab, driven over CDP. Sign in yourself
# and open an expendable Notepad. These overwrite the text in that window, and they
# overwrite the local clipboard, then restore any text it held when the script exits. Its
# contents are never printed. See docs/agent-guide/remote-desktop.md.
set -euo pipefail

here=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
url=https://demo.tsplus.net/software/html5.html
x=727
y=364
out=${XDG_RUNTIME_DIR:-/tmp}/rdp-lab

usage() {
	cat <<'EOF'
Usage: portal-test.sh [--url PREFIX] [--x N] [--y N] [--dir PATH] COMMAND

  inspect       Page, client, and canvas facts, plus a screenshot; sends no input
  type          Coordinate click and typing, then a screenshot
  copy-timing   Hold Ctrl+C for 5 to 100 ms; compare arrival with the local clipboard
  paste         Local to remote with Ctrl+V and Chromium's explicit paste command
  menu          Clipboard menu: To clip and To IME with non-ASCII text, then ToEnv
  stale-probe   Find what makes a paste insert old remote text (see the guide)

X and Y are CSS pixels inside Notepad. Screenshot pixels divided by devicePixelRatio
give CSS pixels.
EOF
}

while (($#)); do
	case $1 in
	--url) url=$2 && shift 2 ;;
	--x) x=$2 && shift 2 ;;
	--y) y=$2 && shift 2 ;;
	--dir) out=$2 && shift 2 ;;
	-h | --help) usage && exit 0 ;;
	*) break ;;
	esac
done
(($#)) || {
	usage >&2
	exit 2
}
mkdir -p "$out"

run() { timeout 40 node "$here/cdp-tab.mjs" "$url" "$1"; }
clip_read() { timeout 3 xclip -o -selection clipboard 2>/dev/null; }
clip_set() { printf '%s' "$1" | timeout 3 xclip -selection clipboard >/dev/null 2>&1 || true; }

had_text=0
saved=''
protect_clipboard() {
	if saved=$(clip_read); then had_text=1; fi
	trap 'if ((had_text)); then clip_set "$saved"; fi' EXIT
}

key() { printf '{"op":"key","key":"%s","ctrl":true,"holdMs":%s}' "$1" "${2:-30}"; }
wait_ms() { printf '{"op":"wait","ms":%s}' "$1"; }
click() { printf '{"op":"click","x":%s,"y":%s},%s' "$x" "$y" "$(wait_ms 600)"; }
delete_key='{"op":"key","key":"Delete","code":"Delete","vk":46}'
clear_text() { printf '%s,%s,%s,%s,%s' "$(click)" "$(key a)" "$(wait_ms 400)" "$delete_key" "$(wait_ms 500)"; }
paste_key='{"op":"key","key":"v","ctrl":true,"commands":["paste"]}'
read_back() {
	printf '%s,%s,%s,%s,%s,{"op":"eval","label":"remote text","expr":"JSON.stringify(W.clipbuffer)"}' \
		"$(wait_ms 1300)" "$(key a)" "$(wait_ms 500)" "$(key c)" "$(wait_ms 700)"
}
open_menu='{"op":"key","key":"F11","code":"F11","vk":122,"shift":true},{"op":"wait","ms":600}'
close_menu='{"op":"eval","label":"close menu","gesture":true,"expr":"(()=>{const b=document.getElementById(\"JWTS_cb3\");if(b&&b.offsetParent){b.click();return \"closed\"};return \"not open\"})()"},{"op":"wait","ms":300}'
press_button() {
	printf '{"op":"eval","label":"press %s","gesture":true,"expr":"(()=>{const t=document.getElementById(\\"JWTS_clippy\\");t.value=\\"%s\\";document.getElementById(\\"%s\\").click();return t.value.length})()"}' "$1" "$3" "$2"
}

cmd_inspect() {
	run "[{\"op\":\"eval\",\"label\":\"page\",\"expr\":\"JSON.stringify({title:document.title,w:innerWidth,h:innerHeight,dpr:devicePixelRatio,visible:document.visibilityState,focus:document.hasFocus(),secure:isSecureContext,canvases:document.querySelectorAll('canvas').length,elements:document.querySelectorAll('body *').length})\"},
{\"op\":\"eval\",\"label\":\"client\",\"expr\":\"JSON.stringify({W:typeof W,clipboard:W.clipboard,openonclipblur:W.openonclipblur,clipuse:W.clipuse,asyncRead:!!(navigator.clipboard&&navigator.clipboard.readText),asyncWrite:!!(navigator.clipboard&&navigator.clipboard.writeText)})\"},
{\"op\":\"shot\",\"file\":\"$out/portal-inspect.png\"}]"
}

cmd_type() {
	run "[$(click),{\"op\":\"type\",\"text\":\"Agent canvas test 123: Hello, World! (a-b_c)\\n\"},$(wait_ms 1500),{\"op\":\"shot\",\"file\":\"$out/portal-typed.png\"}]"
}

cmd_copy_timing() {
	local hold tok sentinel got result
	protect_clipboard
	for hold in 5 20 50 100 5 20 50 100; do
		tok="copytest$hold$RANDOM"
		sentinel="SENTINEL$RANDOM"
		run "[{\"op\":\"focus\"},$(clear_text),{\"op\":\"type\",\"text\":\"$tok\"},$(wait_ms 1300),$(key a),$(wait_ms 500)]" >/dev/null
		clip_set "$sentinel"
		run "[{\"op\":\"focus\"},{\"op\":\"copyTiming\",\"token\":\"$tok\",\"holdMs\":$hold},$(wait_ms 700)]" | grep '^copy hold' || true
		got=$(clip_read || true)
		case $got in
		"$tok") result='local clipboard exact' ;;
		*"$tok"*) result='local clipboard contains it' ;;
		"$sentinel") result='local clipboard unchanged' ;;
		*) result="local clipboard other (length ${#got})" ;;
		esac
		printf '  -> %s\n' "$result"
	done
}

cmd_paste() {
	local sent="LocalPasteTest$RANDOM"
	protect_clipboard
	clip_set "$sent"
	run "[{\"op\":\"focus\"},$(clear_text),$paste_key,$(read_back)]" | grep 'remote text' || true
	printf 'expected: "%s"\n' "$sent"
}

cmd_menu() {
	local text='Clip cafeé ñ € ✓ 日本語 / second line' sent tok got
	protect_clipboard
	echo '== To clip =='
	run "[{\"op\":\"focus\"},$close_menu,$(clear_text),$open_menu,$(press_button 'To clip' JWTS_cb2 "$text"),$(wait_ms 1000),$close_menu,$(click),$(read_back)]" |
		grep -E 'press|remote text|EXCEPTION' || true
	echo '== To IME =='
	run "[{\"op\":\"focus\"},$(clear_text),$open_menu,$(press_button 'To IME' JWTS_cb4 "$text"),$(wait_ms 2000),$close_menu,$(click),$(read_back)]" |
		grep -E 'press|remote text|EXCEPTION' || true
	echo '== ToEnv =='
	sent="SENTINEL$RANDOM"
	tok="ToEnvTest$RANDOM"
	clip_set "$sent"
	run "[{\"op\":\"focus\"},$open_menu,$(press_button ToEnv JWTS_cb10 "$tok"),$(wait_ms 500),$close_menu]" | grep -E 'press|EXCEPTION' || true
	got=$(clip_read || true)
	case $got in
	"$tok") echo 'local clipboard exact' ;;
	"$sent") echo 'local clipboard unchanged' ;;
	*) echo "local clipboard other (length ${#got})" ;;
	esac
}

# Written after the stale paste appeared; the session ended before it could run, so its
# output has never been checked against a live client.
cmd_stale_probe() {
	local hook plog state i t wait_for
	hook='{"op":"eval","label":"hook","expr":"(()=>{if(!window.__pasteLog){window.__pasteLog=[];document.addEventListener(\"paste\",e=>{window.__pasteLog.push((e.clipboardData&&e.clipboardData.getData(\"text\"))||\"<empty>\")},true)};return true})()"}'
	plog='{"op":"eval","label":"paste event saw","expr":"JSON.stringify((window.__pasteLog||[]).splice(0))"}'
	state='{"op":"eval","label":"client state","expr":"JSON.stringify({clipped:W.clipped,ctrlv:W.ctrlv,bufLen:(W.clipbuffer||\"\").length})"}'
	protect_clipboard
	echo '== three pastes in a row, with no remote copy between them =='
	run "[{\"op\":\"focus\"},$hook,$(clear_text)]" >/dev/null
	for i in 1 2 3; do
		t="Seq$i$RANDOM"
		clip_set "$t"
		printf '%s: local %s\n' "$t" "$([[ "$(clip_read || true)" == "$t" ]] && echo matches || echo differs)"
		run "[{\"op\":\"focus\"},$paste_key,$(wait_ms 1500),$plog,$state]" | grep -E 'paste event|client state' || true
	done
	run "[{\"op\":\"focus\"},$(read_back)]" | grep 'remote text' || true
	echo '== paste after a remote copy, with growing waits =='
	for wait_for in 200 3000 9000; do
		t="Wait$wait_for$RANDOM"
		run "[{\"op\":\"focus\"},{\"op\":\"key\",\"key\":\"End\",\"code\":\"End\",\"vk\":35},$(wait_ms "$wait_for")]" >/dev/null
		clip_set "$t"
		printf '%s: local %s\n' "$t" "$([[ "$(clip_read || true)" == "$t" ]] && echo matches || echo differs)"
		run "[{\"op\":\"focus\"},$state,$paste_key,$(wait_ms 1500),$plog,$(read_back)]" |
			grep -E 'paste event|client state|remote text' || true
	done
}

case $1 in
inspect) cmd_inspect ;;
type) cmd_type ;;
copy-timing) cmd_copy_timing ;;
paste) cmd_paste ;;
menu) cmd_menu ;;
stale-probe) cmd_stale_probe ;;
*) usage >&2 && exit 2 ;;
esac
