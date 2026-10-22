#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 11 && $# -ne 13 && $# -ne 14 ]]; then
	printf 'usage: rex-whichkey REX_CLI CLIENT SESSION ORIGIN_PANE BG FG KEY BORDER MUTED CRITICAL GROUP [WIDTH_FRACTION HEIGHT_FRACTION [POSITION]]\n' >&2
	exit 2
fi
# Rex terminals inherit the target server's CLI directory, not the client's.
rex_cli="$1"
if [[ "$rex_cli" == rex && -n "${REX_BIN_DIR:-}" ]]; then
	rex_cli="$REX_BIN_DIR/rex"
fi
rex=$(command -v "$rex_cli") || {
	printf 'Rex executable not found: %s\n' "$1" >&2
	exit 2
}
[[ -x "$rex" ]] || {
	printf 'Rex must be executable\n' >&2
	exit 2
}
client="$2"
session="$3"
origin="$4"
width_fraction="${12:-1}" height_fraction="${13:-1}"
position="${14:-center}"
case "$position" in
top | bottom | left | right | center) ;;
*)
	printf 'Unknown rendering area: %s\n' "$position" >&2
	exit 2
	;;
esac
for fraction in "$width_fraction" "$height_fraction"; do
	if [[ ! "$fraction" =~ ^(0\.[0-9]*[1-9][0-9]*|1(\.0+)?)$ ]]; then
		printf 'Viewport fractions must be greater than zero and at most one\n' >&2
		exit 2
	fi
done
for color in "${@:5:7}"; do
	if [[ ! "$color" =~ ^#[[:xdigit:]]{6}$ ]]; then
		printf 'Popup colors must be six-digit hex colors\n' >&2
		exit 2
	fi
done
if [[ -t 1 ]]; then printf '\033]2;whichkey-popup\007\033[?25l'; fi
# Inline setup specs live in Rex, not in a second frontend config. Transfer only
# display metadata as JSON; callbacks and action arguments remain server-side.
if [[ -t 0 && -t 1 ]]; then
	REX_WHICHKEY_SNAPSHOT=$("$rex" -C "$client" "do" whichkey_snapshot -s "$session" -b "$origin" --json)
	[[ -n "$REX_WHICHKEY_SNAPSHOT" ]] || {
		printf 'Missing which-key menu snapshot\n' >&2
		exit 1
	}
	export REX_WHICHKEY_SNAPSHOT
fi
prefix=""
page=0
confirmation=""
notice=""
background="" text="" key_style="" border="" muted="" critical="" group="" bold="" normal=""
color_code() {
	local hex="${1#\#}"
	printf '\033[%s;2;%d;%d;%dm' "$2" "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))"
}
accessible_color() {
	# Lift/darken semantic colors just enough to remain legible on the raised surface.
	awk -v color="$1" -v surface="$2" -v minimum="$3" '
    function channel(hex, offset, digits) {
      digits = "0123456789abcdef"
      return (index(digits, tolower(substr(hex, offset, 1))) - 1) * 16 + index(digits, tolower(substr(hex, offset + 1, 1))) - 1
    }
    function linear(v) { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055)^2.4 }
    function lum(r, g, b) { return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) }
    function contrast(a, b) { return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05) }
    BEGIN {
      background = lum(channel(surface, 2), channel(surface, 4), channel(surface, 6))
      target = contrast(1, background) >= contrast(0, background) ? 255 : 0
      r = channel(color, 2); g = channel(color, 4); b = channel(color, 6)
      for (step = 0; step <= 20; step++) {
        amount = step / 20
        rr = int(r * (1 - amount) + target * amount + 0.5)
        gg = int(g * (1 - amount) + target * amount + 0.5)
        bb = int(b * (1 - amount) + target * amount + 0.5)
        if (contrast(lum(rr, gg, bb), background) >= minimum) break
      }
      printf "#%02x%02x%02x", rr, gg, bb
    }'
}
source @REX_WHICHKEY_DIRECTORY@/theme.sh
cleanup() {
	terminal_theme_restore
	if [[ -t 1 ]]; then printf '\033[0m\033[?25h'; fi
}
trap cleanup EXIT
trap 'exit 0' INT TERM
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
	command -v awk >/dev/null || {
		printf 'awk is required\n' >&2
		exit 1
	}
	terminal_theme_read
	surface="$(terminal_theme_color background "$5")"
	background="$(color_code "$surface" 48)"
	text="$(color_code "$(accessible_color "$(terminal_theme_color foreground "$6")" "$surface" 4.5)" 38)"
	key_style="$(color_code "$(accessible_color "$(terminal_theme_color key "$7")" "$surface" 4.5)" 38)"
	border="$(color_code "$(accessible_color "$(terminal_theme_color border "$8")" "$surface" 3)" 38)"
	muted="$(color_code "$(accessible_color "$(terminal_theme_color muted "$9")" "$surface" 4.5)" 38)"
	critical="$(color_code "$(accessible_color "$(terminal_theme_color critical "${10}")" "$surface" 4.5)" 38)"
	group="$(color_code "$(accessible_color "$(terminal_theme_color group "${11}")" "$surface" 4.5)" 38)"
	bold=$'\033[1m'
	normal=$'\033[22m'
fi
resized=0 terminal_size=""
trap 'resized=1' WINCH
read_key() {
	local status size
	while true; do
		if [[ -n "$terminal_pending_keys" ]]; then
			key="${terminal_pending_keys:0:1}"
			terminal_pending_keys="${terminal_pending_keys:1}"
			return 0
		fi
		resized=0 key=""
		if IFS= read -r -s -n 1 -t 0.25 key; then
			if ((resized)); then render; fi
			if ! terminal_key_filter "$key"; then continue; fi
			[[ -n "$key" ]]
			return
		else
			status=$?
		fi
		# Rex can resize the grid without delivering SIGWINCH to this process.
		if [[ -t 0 ]] && command -v stty >/dev/null; then
			size="$(stty size 2>/dev/null || true)"
			if [[ "$size" != "$terminal_size" ]]; then resized=1; fi
		fi
		if ((resized)); then render; fi
		if ((status <= 128 && ! resized)); then return 1; fi
	done
}
render() {
	local rows="${LINES:-20}" cols="${COLUMNS:-72}" size rendered metadata dimensions mode=plain
	if [[ -t 0 && -t 1 ]]; then mode=ansi; fi
	# The overlay keeps full-window bounds. Measure once; content placement and
	# shrinking are already handled by Areas.render inside the Lua renderer.
	if [[ -t 0 ]] && command -v stty >/dev/null; then
		size="$(stty size 2>/dev/null || true)"
		terminal_size="$size"
		if [[ "$size" =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
			rows="${BASH_REMATCH[1]}"
			cols="${BASH_REMATCH[2]}"
		fi
	fi
	if [[ ! "$rows" =~ ^[0-9]+$ ]]; then rows=20; fi
	if [[ ! "$cols" =~ ^[0-9]+$ ]]; then cols=72; fi
	if [[ "$mode" == ansi ]]; then
		if ! dimensions=$("$rex" -C "$client" "do" @REX_WHICHKEY_DIRECTORY@/resize.lua -s "$session" -b "$origin" "rows=0" "directory=@REX_WHICHKEY_DIRECTORY@" "position=$position" --json); then
			printf 'Could not calculate which-key rendering area\n' >&2
			return 1
		fi
		dimensions="${dimensions//[$' \t\r\n']/}"
		if [[ ! "$dimensions" =~ ^\[([1-9][0-9]*),([1-9][0-9]*)\]$ ]]; then
			printf 'Invalid which-key window dimensions\n' >&2
			return 1
		fi
		cols="${BASH_REMATCH[1]}" rows="${BASH_REMATCH[2]}"
	fi
	rendered="$(@REX_WHICHKEY_LUA@ @REX_WHICHKEY_DIRECTORY@/main.lua render \
		"$prefix" "$page" "$confirmation" "$notice" "$rows" "$cols" \
		"$width_fraction" "$height_fraction" "${REX_WHICHKEY_ASCII:-0}" \
		"$text" "$key_style" "$border" "$muted" "$critical" "$group" "$bold" "$normal" "$background" "$mode" "$position")"
	metadata="${rendered%%$'\n'*}"
	if [[ ! "$metadata" =~ ^[0-9]+[[:space:]][1-9][0-9]*[[:space:]][1-9][0-9]*$ ]]; then
		printf 'Invalid renderer paging metadata\n' >&2
		return 1
	fi
	read -r page pages _ <<<"$metadata"
	printf '%s' "${rendered#*$'\n'}"
	if [[ ! -t 1 ]]; then printf '\n'; fi
}

while true; do
	render
	read_key || exit 0
	response="$(@REX_WHICHKEY_LUA@ @REX_WHICHKEY_DIRECTORY@/main.lua key "$prefix" "$page" "$confirmation" "$key" "$pages")"
	mapfile -t event <<<"$response"
	if [[ ${#event[@]} -ne 6 || ! "${event[2]}" =~ ^[0-9]+$ || ! "${event[5]}" =~ ^(true|false)$ ]]; then
		printf 'Invalid menu input response\n' >&2
		exit 1
	fi
	prefix="${event[1]}" page="${event[2]}" confirmation="${event[3]}"
	case "${event[0]}" in
	quit) exit 0 ;;
	render) continue ;;
	dispatch)
		choice="${event[4]}"
		confirmed="${event[5]}"
		;;
	*)
		printf 'Unknown menu input response\n' >&2
		exit 1
		;;
	esac
	# The shared spec resolves this lhs on the Rex side; no shell action map.
	if cli_output=$("$rex" -C "$client" "do" whichkey_dispatch -s "$session" -b "$origin" "lhs=$choice" "confirmed=$confirmed" 2>&1); then exit 0; fi
	notice="${cli_output%%$'\n'*}"
	if [[ -z "$notice" ]]; then notice='Check Remote Control / reload init.lua'; fi
	page=0
	render
	read_key || true
	exit 1
done
