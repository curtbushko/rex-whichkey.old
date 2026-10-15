#!/usr/bin/env bash
set -euo pipefail
for command in dirname sleep; do command -v "$command" >/dev/null || exit 1; done
# shellcheck source=lua/whichkey/theme.sh
source "${1:-$(dirname "${BASH_SOURCE[0]}")/../lua/whichkey/theme.sh}"
terminal_theme_parse '10;rgb:d3d3/c6c6/aaaa'
[[ ${terminal_colors[10]} == '#d3c6aa' ]]
terminal_theme_parse '11;rgb:f/0/8'
[[ ${terminal_colors[11]} == '#ff0088' ]]
terminal_theme_parse '4;6;rgb:abc/123/fff'
[[ ${terminal_colors['4;6']} == '#ab12ff' ]]
for reply in '10;rgb:fffff/0/0' '10;rgb:zz/00/00' '4;999;rgb:ff/00/00' '11;rgb:ff/00/00;extra' "10;rgb:\$(touch nope)/0/0"; do
	if terminal_theme_parse "$reply"; then
		printf 'Accepted invalid reply: %s\n' "$reply" >&2
		exit 1
	fi
done
terminal_colors=()
terminal_theme_collect < <(printf 'v\033]10;rgb:ffff/eeee/dddd\007s\033]11;rgb:1111/2222/3333\033\\\033]4;1;rgb:ffff/0000/0000\007\033]4;6;rgb:0000/ffff/ffff\007')
[[ ${terminal_colors[10]} == '#ffeedd' && ${terminal_colors[11]} == '#112233' ]]
[[ ${terminal_colors['4;1']} == '#ff0000' && ${terminal_colors['4;6']} == '#00ffff' ]]
[[ $terminal_pending_keys == vs ]]
[[ $(terminal_theme_color critical '#123456') == '#ff0000' ]]
[[ $(terminal_theme_color group '#123456') == '#00ffff' ]]
[[ $(terminal_theme_color key '#123456') == '#123456' ]]
[[ $(terminal_theme_color background '#123456') == '#2e3a47' ]]
[[ $(terminal_theme_surface '#232a2e' '#d3c6aa') == '#383d3d' ]]
[[ $(terminal_theme_surface '#ffffff' '#000000') == '#e0e0e0' ]]
[[ $(terminal_theme_surface '#000000' '#ffffff') == '#1f1f1f' ]]
[[ $(terminal_theme_surface '#000000' '#000000') == '#1f1f1f' ]]
[[ $(terminal_theme_surface '#ffffff' '') == '#e0e0e0' ]]
[[ $(terminal_theme_surface '#232a2e' '#242b2f') != '#232a2e' ]]
[[ $(terminal_theme_color foreground '#123456') == '#ffeedd' ]]
terminal_theme_parse '4;3;rgb:ffff/ffff/0000'
terminal_theme_parse '4;8;rgb:8888/8888/8888'
[[ $(terminal_theme_color key '#123456') == '#ffff00' ]]
[[ $(terminal_theme_color border '#123456') == '#888888' ]]
[[ $(terminal_theme_color muted '#123456') == '#888888' ]]
terminal_colors=()
terminal_pending_keys=''
terminal_theme_collect < <(printf '\033]10;rgb:bad\007q\033')
[[ ${#terminal_colors[@]} == 0 && $terminal_pending_keys == $'q\033' ]]
terminal_pending_keys=''
terminal_theme_collect < <(printf '\033]10;rgb:ffff/eeee')
[[ -z $terminal_pending_keys && ${#terminal_colors[@]} == 0 ]]
terminal_theme_collect < <(
	printf '\033]10;'
	printf '%0300d' 0
	printf '\007q'
)
[[ $terminal_pending_keys == q && ${#terminal_colors[@]} == 0 ]]
start=${EPOCHREALTIME/./}
terminal_theme_collect < <(sleep 1)
elapsed=$((${EPOCHREALTIME/./} - start))
[[ $elapsed -lt 900000 ]] || {
	printf 'Theme query exceeded total time budget\n' >&2
	exit 1
}
[[ $(terminal_theme_color background '#123456') == '#123456' ]]
[[ $(terminal_theme_read </dev/null) == '' ]]
printf 'Rex OSC theme parsing, semantic colors, fallbacks and typeahead: passed\n'
