# Test parity — gnome-connections-rb vs. origin/master

## Upstream has no unit/integration test suite

`git ls-tree -r --name-only origin/master | grep -iE 'test|spec'` returns
**nothing**. Upstream gnome-connections (Vala/Meson) ships no `tests/`
directory, no Meson `test()` targets, nothing. So "every upstream test is
ported" is **vacuously true**: 0 of 0. This is not itself a port gap.

## The port's RSpec harness: previously a 0-example shell, now real coverage — re-verified fresh this round

The prior two audit rounds tracked this gap through three states:
1. (two rounds ago) the dev shell's own banner command crashed outright.
2. (one round ago, commit `ec3297b`) the crash was fixed, but `spec/` still
   held zero `*_spec.rb` files — a suite that runs but proves nothing. That
   round's report refused to credit "the crash is fixed" as "there is
   coverage."
3. (this round, commit `9c27610`) four real spec files were added.

This round re-ran the exact invocation from scratch rather than trusting the
commit message:

```
nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format", "progress", "--require", "spec_helper", "spec"])'
```

Result, this session:

```
spec_helper: kettle/test/rspec unavailable (cannot load such file -- kettle/test/rspec); running without its harness helpers.
...
61 examples, 0 failures
```

`spec/` now holds:

| File | Class under test | Coverage |
|---|---|---|
| `spec/credentials_spec.rb` | `Credentials` (`lib/connection.rb`) | lookup/store/delete round-trip, `0600` file mode, `.compact`-ing nil fields, corrupt-JSON recovery |
| `spec/settings_spec.rb` | `Settings` (`lib/settings.rb`) | defaults, `first_run=`/`window_size=` persistence round-trip, type coercion, `apply_to`/`remember`, corrupt-JSON recovery |
| `spec/connection_spec.rb` | `Connection` (`lib/connection.rb`), via `VncConnection` | uri parse/join, `visible_name`, property-change observers, `while_loading`, save-to-database, credential storage, `handle_auth`, abstract-method contract |
| `spec/database_spec.rb` | `Database` (`lib/database.rb`) | `.protocols`, `get_connections`/`get_connection`, `add_connection` per scheme, `find_connection_by_uri`, `delete_connection`, property round-trip |

This is a genuine, re-verified close of the prior round's headline finding:
the suite is no longer "present in name only." It covers the model and
persistence layer with real assertions (`expect`, not just "does not raise"),
including corrupt-input and round-trip cases. **61 of 61 examples pass,
re-run cold this session, not taken from the commit message.**

- `bundle exec rspec` (the conventional invocation) still fails the same way
  as every prior round: `can't find executable rspec for gem rspec-core.
  rspec-core is not currently included in the bundle` (re-verified this
  session). Only the dev shell's own `ruby -e ...RSpec::Core::Runner.run...`
  form works. This second-order gap is unchanged and still open: a
  contributor who types the Ruby-standard `bundle exec rspec` instead of
  copying the banner's exact one-liner still hits a wall. `TEST_PARITY.md`
  (new this round) documents the working form; it does not fix the
  underlying `bundle exec rspec` failure.
- **What the new specs do not cover**: no widget/view/dialog class
  (`lib/window.rb`, `lib/topbar.rb`, `lib/collection_view.rb`,
  `lib/dialogs_window.rb`, the three preferences windows, etc.) has an
  RSpec example. That is by design — those need a GTK main loop, which is
  the drive script's job, not RSpec's — but it means "RSpec passes" says
  nothing about any of the 19 widget-backed `lib/*.rb` files. Only the drive
  script (below) exercises those.

## The suite that actually exercises the port is `test/drive_gnome_connections.rb`

Re-run fresh this session (not reused from a prior round's log):

```
nix develop --command xvfb-run -a ruby test/drive_gnome_connections.rb
```

→ **157 of 157 checks passed, `DRIVE OK`**, confirming the runtime gate
figure given for this round. Also re-ran via `rake drive`
(`nix develop --command bash -lc 'rake drive'`) — same 157/157 — confirming
the Rakefile wiring from `ec3297b` still works after this round's changes.

It is a single long script (50 numbered scenarios, `[0]`–`[49]`), covering:
onboarding carousel, empty state, the new-connection assistant (VNC/RDP
default/switch), search/filter, opening a connection and its VNC-unavailable
fallback, the notification bar and its dismissal, the display header bar and
back/disconnect, the three preferences windows, the actions popover and
delete-with-undo, certificate verification/change/authentication dialogs
(including credential round-trip and `.vnc` file import), CLI argument
parsing, keyboard shortcuts (`F1`, `F11`, `Ctrl+Q`,
`win.show-help-overlay`), the About dialog's fields, window-size settings
persistence, and shutdown/quit.

**Caveat the harness itself documents, re-confirmed this round**: no
`gtk-vnc`, `gtk-frdp`, or `spice-gtk` typelib exists anywhere in this fleet's
Nix store (re-checked with `find /nix/store -iname "*vnc*.typelib" ...`,
returns nothing — see `FINDINGS.md`), so every actual remote-desktop session
necessarily falls over to the "protocol unavailable" path. The driver tests
that the fallback behaves correctly; it cannot and does not test an actual
VNC/RDP/SPICE session succeeding, because no environment in this fleet can
provide one. "157 checks passed" does not include "a remote desktop was
displayed," in this run or any run this port could produce here.

## The runtime gate's component count does not reconcile with this audit's unit count

This round's gate reports "157 checks passed... covering 26 components."
`.reports/component-identification.md` independently derives **24**
upstream-to-port file-level units (confirmed again this round — no `lib/*.rb`
file was added or removed since that count was taken; only `spec/*.rb` and
root-level `.md` ledgers changed). `test/drive_gnome_connections.rb` itself
carries no per-scenario "component" tag anywhere in its source
(`grep -n component test/drive_gnome_connections.rb` → no matches), so
neither "26" nor the prior round's "21" can be traced to anything in this
repository. Two different rounds, two different numbers, neither reconciled
to a concrete list, for a port whose own file-level unit count has not
changed. This is flagged again, by name, rather than treated as a rounding
difference: **a drive run's "N components" figure is not verifiable from
inside this repository and should not be taken as a precise coverage claim
until something in `test/` actually emits a component list.**

## Verdict

- Upstream test parity: trivially met (0 upstream tests).
- Port's RSpec suite: **closed as a gap this round** — real spec files,
  real assertions, 61/61 passing, re-verified cold. `bundle exec rspec`
  remains broken as a convenience path (minor, documented, open).
- Port's widget/view/dialog layer: **not covered by RSpec at all, only by
  the drive script** — worth stating plainly rather than letting "61
  examples, 0 failures" read as broader than it is.
- Port's actual UI verification (`test/drive_gnome_connections.rb`):
  substantial, independently re-run this session, 157/157 confirmed, with
  the VNC/RDP/SPICE-unavailable caveat unchanged.
- The gate's "26 components" figure: **unreconciled**, same open issue as
  last round's "21," now with a different number and still no source for
  either inside this repository.
