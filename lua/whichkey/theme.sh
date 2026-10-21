#!/usr/bin/env bash
# Sourced by rex-whichkey. Query the inherited theme before painting any colors.
set -euo pipefail
declare -A terminal_colors=()
terminal_pending_keys='' terminal_theme_stty=''
terminal_input_osc=0 terminal_input_escape=0

terminal_theme_parse() {
	local pattern='^(10|11|4;[0-9]+);rgb:([[:xdigit:]]{1,4})/([[:xdigit:]]{1,4})/([[:xdigit:]]{1,4})$'
	local id component maximum value color='#'
	[[ $1 =~ $pattern ]] || return 1
	id=${BASH_REMATCH[1]}
	local components=("${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}")
	case "$id" in 10 | 11 | 4\;1 | 4\;3 | 4\;6 | 4\;8) ;; *) return 1 ;; esac
	for component in "${components[@]}"; do
		maximum=$(((1 << (4 * ${#component})) - 1))
		value=$(((16#$component * 255 + maximum / 2) / maximum))
		printf -v color '%s%02x' "$color" "$value"
	done
	terminal_colors[$id]=$color
}

terminal_theme_collect() {
	local byte='' frame='' deadline status oversized=0 remaining timeout
	terminal_input_osc=0 terminal_input_escape=0
	# Theme replies are normally immediate. Never hold the first frame for a
	# missing palette slot; use the supplied fallbacks after a 50 ms total budget.
	deadline=$((${EPOCHREALTIME/./} + 50000))
	while true; do
		remaining=$((deadline - ${EPOCHREALTIME/./}))
		if ((remaining <= 0)); then break; fi
		printf -v timeout '0.%06d' "$remaining"
		if IFS= read -r -s -N 1 -t "$timeout" byte; then
			:
		else
			status=$?
			if ((status <= 128)); then break; fi
			continue
		fi
		if [[ -z "$frame" ]]; then
			if [[ "$byte" == $'\033' ]]; then frame=$byte; else terminal_pending_keys+=$byte; fi
		elif [[ "$frame" == $'\033' && "$byte" != ']' ]]; then
			terminal_pending_keys+="$frame$byte"
			frame=''
		else
			frame+=$byte
			if [[ "$byte" == $'\007' || "$frame" == *$'\033\\' ]]; then
				frame=${frame#$'\033]'}
				frame=${frame%$'\007'}
				frame=${frame%$'\033\\'}
				if ((! oversized)); then terminal_theme_parse "$frame" || true; fi
				frame='' oversized=0
				if ((${#terminal_colors[@]} == 6)); then break; fi
			elif ((${#frame} > 256)); then
				frame=$'\033]' oversized=1
			fi
		fi
	done
	# Preserve a user's lone Escape, but never feed incomplete OSC replies to
	# menu navigation (their leading Escape would close the popup).
	if [[ "$frame" == $'\033' ]]; then
		terminal_pending_keys+=$frame
	elif [[ -n "$frame" ]]; then
		terminal_input_osc=1
		if [[ "$frame" == *$'\033' ]]; then terminal_input_escape=1; fi
	fi
}

# A reply arriving after the startup budget is terminal traffic, not menu input.
# Keep OSC state across reads so even fragmented late replies cannot close the
# popup with their leading Escape or accidentally dispatch one of their bytes.
terminal_key_filter() {
	local next=''
	if ((terminal_input_osc)); then
		if [[ "$1" == $'\007' || ($terminal_input_escape == 1 && "$1" == $'\\') ]]; then
			terminal_input_osc=0
		fi
		terminal_input_escape=0
		if [[ "$1" == $'\033' ]]; then terminal_input_escape=1; fi
		return 1
	fi
	if [[ "$1" == $'\033' ]] && IFS= read -r -s -N 1 -t 0.005 next; then
		if [[ "$next" == ']' ]]; then
			terminal_input_osc=1
			return 1
		fi
		terminal_pending_keys="$next$terminal_pending_keys"
	fi
	return 0
}

terminal_theme_restore() {
	if [[ -n "$terminal_theme_stty" ]]; then
		stty "$terminal_theme_stty" 2>/dev/null || true
		terminal_theme_stty=''
	fi
}

terminal_theme_read() {
	[[ -t 0 && -t 1 ]] || return 0
	command -v stty >/dev/null || return 0
	terminal_theme_stty=$(stty -g 2>/dev/null) || return 0
	if ! stty -echo -icanon min 1 time 0; then
		terminal_theme_restore
		return 0
	fi
	printf '\033]10;?\007\033]11;?\007\033]4;1;?\007\033]4;3;?\007\033]4;6;?\007\033]4;8;?\007'
	terminal_theme_collect
	terminal_theme_restore
}

terminal_theme_surface() {
	# A modest foreground blend creates an elevated surface on dark and light
	# themes without depending on arbitrary ANSI black/white palette entries.
	local bg=${1#\#} fg=${2#\#} target color='#' channel value
	local r=$((16#${bg:0:2})) g=$((16#${bg:2:2})) b=$((16#${bg:4:2}))
	if ((r * 299 + g * 587 + b * 114 < 128000)); then target=ffffff; else target=000000; fi
	fg=${fg:-$target}
	for channel in 0 2 4; do
		value=$(((16#${bg:channel:2} * 88 + 16#${fg:channel:2} * 12 + 50) / 100))
		printf -v color '%s%02x' "$color" "$value"
	done
	# Also distinguish the surface when the theme has identical/near-identical
	# foreground and background, or rounding would erase the difference.
	if [[ $color == "#${bg,,}" ]]; then
		terminal_theme_surface "$1" "#$target"
	else
		printf '%s' "$color"
	fi
}

terminal_theme_color() {
	local id
	if [[ $1 == background && -n ${terminal_colors[11]:-} ]]; then
		terminal_theme_surface "${terminal_colors[11]}" "${terminal_colors[10]:-}"
		return
	fi
	case "$1" in
	foreground) id=10 ;;
	background) id=11 ;;
	key) id='4;3' ;;
	border | muted) id='4;8' ;;
	critical) id='4;1' ;;
	group) id='4;6' ;;
	*) return 1 ;;
	esac
	printf '%s' "${terminal_colors[$id]:-$2}"
}
