# Test parity ledger — gnome-connections-rb

## Upstream

`git ls-tree -r --name-only origin/master` has no `tests/`, `test/`, or
`*_test.vala` anywhere in the tree, and `meson.build` defines no `test()`
target. **Upstream ships zero automated tests.** Test parity with upstream is
therefore 0/0 — trivially met — and everything below is coverage this port
carries *beyond* upstream's own bar, not a gap against it.

## RSpec (`spec/`)

`spec/spec_helper.rb` previously crashed on `require "kettle/test/rspec"`
when that gem could not be resolved; fixed in `ec3297b`, re-verified this
round with the dev shell's own invocation:

```
nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format", "progress", "--require", "spec_helper", "spec"])'
```

`bundle exec rspec` (the conventional invocation) still fails with a
bundler gem-resolution error in this offline Nix dev shell — re-checked this
round, same failure, not something this round's work can fix without network
access to resolve `kettle-test`'s dependency graph. **Use the `ruby -e
...RSpec::Core::Runner.run...` form above** (also printed by the dev shell's
own banner), not `bundle exec rspec`, until `kettle-test` is resolvable
offline.

As of this round, `spec/` holds real unit coverage, not an empty harness:

| File | Class under test | Examples |
|---|---|---|
| `spec/credentials_spec.rb` | `Credentials` (lib/connection.rb) | lookup/store/delete round-trip, `0600` file mode, `.compact`-ing nil fields, corrupt-JSON recovery |
| `spec/settings_spec.rb` | `Settings` (lib/settings.rb) | defaults, `first_run=`/`window_size=` persistence round-trip, type coercion, `apply_to`/`remember`, corrupt-JSON recovery |
| `spec/connection_spec.rb` | `Connection` (lib/connection.rb), via `VncConnection` | uri parse/join, `visible_name`, property-change observers (named + wildcard), `while_loading`, save-to-database, credential storage, `handle_auth`, abstract-method contract |
| `spec/database_spec.rb` | `Database` (lib/database.rb) | `.protocols`, `get_connections`/`get_connection`, `add_connection` per scheme, `find_connection_by_uri` (exact and port-omitted), `delete_connection`, boolean/integer property round-trip |

**61 examples, 0 failures** (re-verified this round via the invocation
above). These are unit-level: no GTK main loop, no window. They exercise the
model/persistence layer directly, which is what was missing — the drive
script below exercises the UI layer that sits on top of it.

## Drive script (`test/drive_gnome_connections.rb`)

Not RSpec: a headless, scripted run of the real GTK application under Xvfb,
driving the main loop and asserting on live widget state (see
`.claude/skills/ruby-gtk-testing`). This is deliberately kept as a separate
harness rather than folded into RSpec, since it needs a GTK main loop and a
display connection that per-example RSpec isolation does not provide.

```
rake drive
# or: nix develop --command xvfb-run -a ruby test/drive_gnome_connections.rb
```

Re-run this round: **157 of 157 checks, `DRIVE OK`**, across 50 `d.step`
scenarios spanning all 24 units in `PORTING.md`'s mapping (see
`COMPONENT_PARITY.md` for the step-to-unit tagging).

## Extra: both harnesses stay, with a clear division of labor

- `spec/*_spec.rb` — fast, isolated, unit-level: the model and persistence
  classes (`Connection`, `Credentials`, `Settings`, `Database`,
  `VncConnection`/`RdpConnection` as concrete stand-ins for the abstract
  base). Runs without a display.
- `test/drive_gnome_connections.rb` — slow, end-to-end, UI-level: everything
  that needs a real widget tree and a running main loop. Runs under Xvfb.

Neither replaces the other. A future change to the model layer should add or
update a `spec/*_spec.rb` example; a future change to a widget, dialog, or
window should add a `d.step` to the drive script.

## What neither harness can cover: real remote-desktop sessions

No per-protocol remote-session test exists for VNC/RDP/SPICE, and none can
be written in this environment: `gtk-vnc`/`gtk-frdp`/`spice-gtk` ship no
GObject-Introspection typelib anywhere this fleet runs (see `FINDINGS.md`),
so there is no real `Vnc.Display`/`FrdpDisplay`/`Spice.Display` to drive or
assert against. The drive script's scenario covering VNC (step "VNC is
unavailable here, so it reports the error and falls back") exercises the
fallback path correctly and is the most that can be tested honestly today.
If a working typelib for any of the three ever becomes available in this
fleet's dev shell, add a drive-script scenario that actually connects and
record it here.
