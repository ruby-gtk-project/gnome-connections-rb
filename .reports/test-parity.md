# Test parity — gnome-connections-rb vs. origin/master

## Upstream has no unit/integration test suite

`git ls-tree -r --name-only origin/master | grep -iE 'test|spec'` returns
**nothing**. Upstream gnome-connections (Vala/Meson) ships no `tests/`
directory, no Meson `test()` targets, nothing. So "every upstream test is
ported" is **vacuously true**: 0 of 0. This is not itself a port gap.

## The port's own RSpec harness: the crash is fixed, but it still has zero tests

- `spec/` holds exactly two files: `spec_helper.rb` and `README.md`. **Zero
  `*_spec.rb` files exist anywhere in the repository.**
- **Re-checked this round, after commit `ec3297b`** (made in response to the
  prior audit round's finding that the banner's own command crashed):
  running the dev shell's printed command exactly as printed —
  `xvfb-run -a ruby -e 'require "rspec/core"; exit
  RSpec::Core::Runner.run(["--format", "progress", "--require",
  "spec_helper", "spec"])'` — now produces:

  ```
  spec_helper: kettle/test/rspec unavailable (cannot load such file -- kettle/test/rspec); running without its harness helpers.
  No examples found.
  Finished in 0.00709 seconds (files took 6.13 seconds to load)
  0 examples, 0 failures
  ```

  `spec_helper.rb` now rescues the unresolvable `kettle/test/rspec` require
  and warns instead of raising, so the banner's own command no longer
  errors out of the box. **This is a genuine, verified fix** of the specific
  defect the prior round reported — re-run fresh this session, not taken on
  faith.
- `bundle exec rspec` still fails the same way it did before this round's
  fix: `can't find executable rspec for gem rspec-core. rspec-core is not
  currently included in the bundle` (re-verified this session). The bundle
  the dev shell hands you still cannot run the *conventional* invocation,
  only the banner's own `ruby -e ...` form. This is a smaller, second-order
  gap worth recording on its own: a contributor who types the Ruby-standard
  `bundle exec rspec` instead of copying the banner's exact one-liner still
  hits a wall.
- **The actual gap that remains, and it is still a gap, not progress toward
  closing it: zero spec files exist.** Fixing the loader so it degrades
  gracefully means the suite now *runs*, but running a suite with 0
  examples is not test coverage — it is a harness with nothing in it. No
  `*_spec.rb` file was added in `ec3297b` or any other commit on this
  branch. The RSpec suite remains **0 of 0 tests, by omission, not by
  design** — there is no claim anywhere that RSpec is deliberately unused
  in favor of the drive script; `spec/README.md` and the gemspec's
  `kettle-test` dependency both imply RSpec is meant to carry real
  coverage. Treat "the crash is fixed" and "there is test coverage" as two
  separate claims — only the first is true.

## The suite that actually exercises the port is `test/drive_gnome_connections.rb`

This is a hand-written, non-RSpec driver that pumps GTK's main loop and
asserts against the live widget tree. It is not what either upstream or the
port's own `spec/README.md` calls "the tests", but it is the thing doing
real verification work here, so it is audited on its own terms:

- Ran it fresh this session:
  `nix develop --command xvfb-run -a ruby test/drive_gnome_connections.rb`
  → **157 of 157 checks passed, `DRIVE OK`**, confirming the runtime gate
  figure given for this round.
- It is a single long script (50 numbered scenarios, `[0]`–`[49]`), covering:
  onboarding carousel, empty state, the new-connection assistant (VNC/RDP
  default/switch), search/filter, opening a connection and its VNC-unavailable
  fallback, the notification bar and its dismissal, the display header bar
  and back/disconnect, the three preferences windows, the actions popover and
  delete-with-undo, certificate verification/change/authentication dialogs
  (including credential round-trip through the credential store and `.vnc`
  file import), CLI argument parsing, keyboard shortcuts (`F1`, `F11`,
  `Ctrl+Q`, `win.show-help-overlay`), the About dialog's fields, window-size
  settings persistence, and shutdown/quit.
- This is a genuinely broad functional sweep — not a shallow smoke test — and
  it is real, demonstrated coverage, which is why `drive_ok=true` is treated
  in this audit as meaningful rather than a self-reported number taken on
  faith.
- **Caveat the harness itself documents**: no `gtk-vnc`, `gtk-frdp`, or
  `spice-gtk` typelib exists in this dev environment, so every actual remote
  desktop session necessarily fails over to the "protocol unavailable" error
  path. The driver *tests that the fallback behaves correctly* — it cannot
  and does not test an actual VNC/RDP/SPICE session succeeding, because no
  environment in this fleet can provide one. That is an honestly-labeled
  environment ceiling, not a suite gap, but it does mean "157 checks passed"
  does not include "a remote desktop was displayed."
- **Re-checked this round**: a `rake drive` task was added in `ec3297b`
  (`task :drive do sh("xvfb-run", "-a", "ruby", ...) end` in the `Rakefile`).
  Running `nix develop --command bash -lc 'rake drive'` reproduces the same
  **157 of 157 checks, `DRIVE OK`** this session. The "not wired into rake"
  gap the prior round recorded is closed. It is still a single monolithic
  script rather than a suite split by scenario, and `rake drive` is not
  `rake test`/`rake spec`/`rake default` — a contributor running the
  project's conventional `rake test` or `rake` still gets nothing that
  exercises this script — but it is now discoverable via `rake -T` rather
  than only via the script's own header comment.

## Verdict

- Upstream test parity: trivially met (0 upstream tests).
- Port's declared RSpec suite: **a gap** — present in name only, backed by a
  broken dependency, zero examples, and a banner command that fails as
  printed. Report this plainly rather than crediting it as "present."
- Port's actual verification (`test/drive_gnome_connections.rb`): substantial
  and independently re-run this session with the claimed 157/157 result
  confirmed, with the VNC/RDP/SPICE-unavailable caveat noted above.
