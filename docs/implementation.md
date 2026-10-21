# Implementation notes

See the [README](../README.md) for installation and configuration.

## Runtime boundaries

- `plugin.lua` runs inside Rex's embedded Lua 5.1. `setup()` registers
  `whichkey`, `whichkey_snapshot`, and `whichkey_dispatch`.
- `config.lua` supplies default menus. User setup can replace them with an inline
  `spec`; it is not necessary to edit installed files.
- `mappings.lua` validates and compiles the spec into a prefix tree. It supports
  arbitrary nesting, attribute scopes, callbacks, conditions, and confirmation.
- `helper.sh` is the input/CLI transport. It requests a versioned JSON menu
  snapshot from Rex once at opening and passes that data to Lua through an
  environment variable. Bash never evaluates menu data as shell commands.
- `main.lua` and `state.lua` turn that snapshot into display/navigation state.
  Callbacks and action arguments stay in Rex; the helper dispatches only the
  selected key sequence plus an explicit confirmation boolean.
- `renderer.lua`, `layout.lua`, and `text.lua` produce Unicode-aware columns,
  centered headings, footers, content sizing, and pagination.
- `theme.sh` queries the inherited terminal theme before painting. It validates
  OSC replies, limits discovery to 50 ms total, restores input settings, and
  preserves typeahead. Late OSC replies are filtered out of menu input.
  NO_COLOR and non-TTY output skip discovery.
- `areas.lua` isolates placement, painting, framing, and the current clipping
  workaround. `resize.lua` measures the originating pane/window through Rex
  APIs and applies changed bounds only. The overlay helper measures geometry
  once per draw and renders once; it needs no content-dependent resize round trip.
  Enabling the native backend would also require restoring that resize step.

The frontend requires Lua 5.4, luautf8, and dkjson. The packaged helper uses Bash
5. The Rex-side modules do not depend on those external Lua libraries.
Popup terminals bypass login initialization and close on completion, including
quick exits. Actions restore focus to the originating pane before dispatch.

## Area API and backends

`top(opts, content_rows)`, `bottom(...)`, `left(...)`, `right(...)`, and
`center(...)` return a common contract: normalized layer `bounds`, a one-based
cell `box`, and its `content` viewport. `resolve` selects a named area.
`render(opts, callback)` measures content then computes its final area;
`draw(area, lines, styles)` produces ANSI output.

These are internal geometry APIs, not user setup options. Width, gap, height
limits, and backend policy belong here. `Areas.options()` admits only position
from configuration so the frontend/controller cannot forward private settings.

- `overlay` uses a full-window layer and paints only the menu region. Resetting
  colors before clearing leaves default-colored cells that show the underlying
  live pane on tested Rex clients. This is observational behavior, not a promised
  transparency API; the layer remains modal.
- `native` uses documented normalized rectangle width/height and local cursor
  coordinates. It is unit-tested but still clipped on Rex build 1101 for some
  offset placements. It must be visually checked before enabling on a future
  client. No speculative version detection switches it automatically.

Unicode box borders use curved glyphs and default-background corner cells.
ASCII boxes use ordinary square corners. Neither is native pixel-rounded clipping.
Bars remain full-width and frameless. Tiny windows reduce margins to retain
navigation help where possible.

## Packaging and checks

`nix/package.nix` substitutes the Lua executable/library paths in `helper.sh`
and the helper/library/Rex CLI paths in `plugin.lua`. Its derivation exports a
`.plugin` attribute containing the generated Lua entry point. The Nix wrapper
contains no menu or shell implementation.

The Home Manager module installs that entry point at
`$XDG_CONFIG_HOME/rex/whichkey/plugin.lua` without taking ownership of `init.lua`.
The module accepts a CLI path and an optional replacement package. Consumers
can instead use `lib.mkPackage` and interpolate `.plugin` into their own config.

`nix flake check` runs Luacheck, Lua 5.1 parser checks for Rex-facing code,
the Lua layout/area/controller/mapping/plugin suites,
Bash theme-reader tests, ShellCheck on the generated helper, CLI integration
with a mock Rex command, and the module's enable/disable/CLI-wiring checks.
No real Rex process, activation, secrets, or host-specific files are required.
The lightweight module check models the `xdg.configFile` option; an installed
consumer should also evaluate its actual Home Manager configuration.

For visual changes, use a temporary Rex config and layer. Always close the exact
created block afterward. Do not deploy, reload, or activate users' configurations
as part of tests.

## Attribution

The standalone layout adapts folke/which-key.nvim's layout engine at revision
`3aab2147e74890957785941f0c1ad87d0a44c15a`, without requiring Neovim buffers,
windows, or highlights. Its Apache-2.0 attribution/license remain in the source
and [lua/whichkey/LICENSE](../lua/whichkey/LICENSE). Preserve those notices when
redistributing the plugin.
