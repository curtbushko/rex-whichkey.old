#!/usr/bin/env bash
set -euo pipefail

# Act as the helper's CLI without contacting Rex or executing any menu actions.
if [[ ${1:-} == "do" ]]; then
	printf '""\n'
	exit 0
fi
if [[ ${1:-} == -C ]]; then
	case "${4:-}" in
	whichkey_snapshot)
		command -v lua >/dev/null || exit 1
		lua - "$REX_PREVIEW_DIRECTORY" <<'LUA'
package.path = arg[1] .. "/?.lua;" .. package.path
local tree = require("mappings").new(require("config"))
print(require("dkjson").encode(tree:snapshot()))
LUA
		;;
	*/resize.lua)
		command -v stty >/dev/null || exit 1
		read -r rows cols < <(stty size)
		printf '[%d,%d]\n' "$cols" "$rows"
		;;
	whichkey_dispatch) ;;
	*) exit 2 ;;
	esac
	exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
	printf 'usage: rex_preview.sh HELPER [top|bottom|left|right|center]\n' >&2
	exit 2
fi
if [[ ! -t 0 || ! -t 1 ]]; then
	printf 'The manual preview needs an interactive terminal\n' >&2
	exit 2
fi
for command in dirname lua stty; do
	command -v "$command" >/dev/null || {
		printf '%s is required; run inside nix develop\n' "$command" >&2
		exit 1
	}
done
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REX_PREVIEW_DIRECTORY="$repo/lua/whichkey"
terminal_settings="$(stty -g)"
cleanup() {
	stty "$terminal_settings" 2>/dev/null || true
	printf '\033[0m\033[?25h\033[?1049l\033[23;0t'
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf '\033[22;0t\033[?1049h'
"$1" "$repo/tests/rex_preview.sh" preview-client preview-session preview-pane \
	'#3d484d' '#d3c6aa' '#dbbc7f' '#859289' '#9da9a0' '#e67e80' '#7fbbb3' \
	1 1 "${2:-bottom}"
