#!/usr/bin/env bash
set -euo pipefail

for command in awk bash chmod cmp dirname grep ln mkdir mktemp mv; do
	command -v "$command" >/dev/null || {
		printf '%s is required\n' "$command" >&2
		exit 1
	}
done
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${1:-}"
if [[ -z "$script" ]]; then
	command -v nix >/dev/null || {
		printf 'nix is required to build the menu\n' >&2
		exit 1
	}
	script="$(cd "$repo" && nix build --no-link --print-out-paths .#default)/bin/rex-whichkey"
fi
[[ -x "$script" ]] || {
	printf 'Menu executable not found: %s\n' "$script" >&2
	exit 1
}
work="$(mktemp -d)"
cleanup() {
	local trash="${REX_WHICHKEY_TEST_TRASH:-$repo/.trash}"
	mkdir -p "$trash"
	mv "$work" "$trash/"
}
trap cleanup EXIT
export REX_TEST_LOG="$work/calls"
mock="$work/rex cli"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
	"printf '%s\\n' \"\$@\" >>\"\$REX_TEST_LOG\"" \
	"exit \"\${REX_TEST_EXIT:-0}\"" >"$mock"
chmod +x "$mock"

run_menu() {
	local input="$1"
	: >"$REX_TEST_LOG"
	printf '%b' "$input" | "$script" "$mock" app-client session-id origin-pane '#3d484d' '#d3c6aa' '#dbbc7f' '#859289' '#9da9a0' '#e67e80' '#7fbbb3' "${REX_TEST_WIDTH_FRACTION:-1}" "${REX_TEST_HEIGHT_FRACTION:-1}" >"$work/output" 2>&1
}
expect_choice() {
	local input="$1" lhs="$2" confirmed="${3:-false}"
	run_menu "$input"
	printf '%s\n' -C app-client "do" whichkey_dispatch -s session-id -b origin-pane "lhs=$lhs" "confirmed=$confirmed" >"$work/expected"
	cmp "$work/expected" "$REX_TEST_LOG"
}

# Rex supplies its own CLI directory, even without an interactive shell PATH.
mkdir -p "$work/rex-bin"
ln -s "$mock" "$work/rex-bin/rex"
printf v | REX_BIN_DIR="$work/rex-bin" "$script" rex app-client session-id origin-pane '#3d484d' '#d3c6aa' '#dbbc7f' '#859289' '#9da9a0' '#e67e80' '#7fbbb3' >"$work/output" 2>&1
grep -q 'lhs=v' "$REX_TEST_LOG"

# A Rex-side inline spec reaches both frontend rendering and key dispatch.
export REX_WHICHKEY_SNAPSHOT='{"version":1,"title":"Custom","position":"center","entries":[{"lhs":"g","action":false,"group":"Tools"},{"lhs":"gx","action":true,"desc":"Custom callback","confirm":true}]}'
expect_choice gxy gx true
unset REX_WHICHKEY_SNAPSHOT

for keys in v s z tn th tl tr t9 wn ws wh wl wr fh fj e c; do
	expect_choice "$keys" "$keys"
done
for keys in tx wx x; do
	expect_choice "${keys}y" "$keys" true
done
# Backspace/Escape from a submenu return to the parent.
expect_choice 't\033v' v
expect_choice 't\177s' s
# Unknown input must not execute an action.
expect_choice '?v' v
# Theme replies arriving after discovery must not close or navigate the menu.
expect_choice '\033]10;rgb:ffff/eeee/dddd\007v' v
expect_choice '\033]11;rgb:1111/2222/3333\033\\v' v
for input in q '\033' '' 'txnq' 'wxnq' 'xnq' 'mnq' 'rkq'; do
	run_menu "$input"
	[[ ! -s "$REX_TEST_LOG" ]]
done
# Keep Neovim-style hints without drawing an outer frame against the PTY grid.
run_menu q
if grep -Eq '╭|╮|╰|╯|│' "$work/output"; then exit 1; fi
grep -q '»' "$work/output"
grep -q '' "$work/output"
grep -q '\[w\]' "$work/output"
if grep -Eq 'Resize|Move|\[r\]|\[m\]' "$work/output"; then exit 1; fi
# ASCII mode keeps text labels and keys without requiring a patched font.
REX_WHICHKEY_ASCII=1 NO_COLOR=1 run_menu q
grep -q 'Rex > Which-key' "$work/output"
if grep -q '' "$work/output"; then exit 1; fi
# Small terminals page the menu instead of writing below its border.
COLUMNS=32 LINES=10 run_menu '\tq'
grep -q 'page 1/2' "$work/output"
grep -q 'page 2/2' "$work/output"
# Actions remain accessible on subsequent pages, and invalid dimensions fall back safely.
COLUMNS=32 LINES=10 expect_choice '\tc' c
COLUMNS=invalid LINES=invalid run_menu q
# Classic layout fills the viewport and centers the title.
COLUMNS=100 LINES=30 REX_WHICHKEY_ASCII=1 NO_COLOR=1 run_menu q
awk '
  NR == 1 {
    left = match($0, /[^ ]/) - 1
    title = $0; sub(/^ +/, "", title); sub(/ +$/, "", title)
    right = 100 - left - length(title)
    if (length($0) != 100 || right - left < 0 || right - left > 1) exit 1
  }
' "$work/output"
# Rex can report a grid wider/taller than the app's visible floating viewport.
COLUMNS=140 LINES=40 REX_TEST_WIDTH_FRACTION=0.5714285714285714 REX_TEST_HEIGHT_FRACTION=0.4615384615384615 REX_WHICHKEY_ASCII=1 NO_COLOR=1 run_menu q
awk '
  NR == 1 {
    left = match($0, /[^ ]/) - 1
    title = $0; sub(/^ +/, "", title); sub(/ +$/, "", title)
    right = 80 - left - length(title)
    if (length($0) != 80 || right - left < 0 || right - left > 1) exit 1
  }
  length($0) > 80 { exit 1 }
' "$work/output"
grep -q 'Command palette' "$work/output"
grep -q 'Esc/q close' "$work/output"
[[ $(grep -c 'Esc' "$work/output") -eq 1 ]]
if grep -q 'Select a highlighted key' "$work/output"; then exit 1; fi
# Full-width output remains short and fits each reported viewport.
for dimensions in '121 42' '100 30' '80 24' '65 18' '32 10'; do
	read -r cols rows <<<"$dimensions"
	COLUMNS="$cols" LINES="$rows" REX_WHICHKEY_ASCII=1 NO_COLOR=1 run_menu q
	awk -v cols="$cols" -v rows="$rows" '
    length($0) > cols { bad = 1 }
    END { if (bad || NR > rows || NR > 11) exit 1 }
  ' "$work/output"
	grep -q 'q close' "$work/output"
	grep -Eq 'Esc/q close|Tab page' "$work/output"
done
# Invalid viewport fractions fail before rendering or dispatch.
for fraction in 0 -0.1 1.1 invalid; do
	if REX_TEST_WIDTH_FRACTION="$fraction" run_menu q; then exit 1; fi
	grep -q 'Viewport fractions' "$work/output"
	[[ ! -s "$REX_TEST_LOG" ]]
done
# CLI errors remain visible and return failure, rather than disappearing silently.
export REX_TEST_EXIT=1
if run_menu 'vq'; then exit 1; fi
grep -q 'Action failed' "$work/output"
[[ -s "$REX_TEST_LOG" ]]
unset REX_TEST_EXIT
printf 'Rex which-key input, confirmation, cancellation and dispatch: passed\n'
