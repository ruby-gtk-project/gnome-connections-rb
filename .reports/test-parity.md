# Test parity — gnome-connections-rb vs. origin/master

## Upstream has no unit/integration test suite

`git ls-tree -r --name-only origin/master | grep -iE 'test|spec'` returns
**nothing**. Upstream gnome-connections (Vala/Meson) ships no `tests/`
directory, no Meson `test()` targets, nothing. So "every upstream test is
ported" is **vacuously true**: 0 of 0. This is not itself a port gap.

## But the port's own RSpec harness is dead, unrun scaffolding

- `spec/` holds exactly two files: `spec_helper.rb` and `README.md`. **Zero
  `*_spec.rb` files exist anywhere in the repository.**
- The dev shell's own printed banner names a command to "run the specs":
  `ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run([...])'`.
  Running it exactly as printed:

  ```
  LoadError: cannot load such file -- kettle/test/rspec
  # ./spec/spec_helper.rb:23:in '<top (required)>'
  No examples found.
  Finished in 0.00006 seconds
  0 examples, 0 failures, 2 errors occurred outside of examples
  ```

  `spec_helper.rb` unconditionally `require "kettle/test/rspec"`, and that
  gem is not resolvable in the dev shell's load path even though
  `gnome-connections-rb.gemspec` declares `kettle-test` (`~> 2.0`) as a
  development dependency.
- `bundle exec rspec` fails even earlier: `can't find executable rspec for
  gem rspec-core. rspec-core is not currently included in the bundle`. The
  bundle the dev shell hands you cannot run RSpec at all, by either the
  banner's own invocation or the conventional one.
- Net result: **this suite has never been executed successfully, and could
  not be if it were run** — not "0 specs, intentionally", but "0 specs,
  behind a broken loader, with a banner command that errors out of the box."
  Per this audit's mandate, that is reported as a gap, not waved through
  because upstream also has nothing to port.

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
- It is also a single monolithic script run manually, not wired into `rake`,
  CI, or any task a contributor would discover without reading
  `test/drive_gnome_connections.rb`'s own header comment. There is no
  `rake drive` or equivalent.

## Verdict

- Upstream test parity: trivially met (0 upstream tests).
- Port's declared RSpec suite: **a gap** — present in name only, backed by a
  broken dependency, zero examples, and a banner command that fails as
  printed. Report this plainly rather than crediting it as "present."
- Port's actual verification (`test/drive_gnome_connections.rb`): substantial
  and independently re-run this session with the claimed 157/157 result
  confirmed, with the VNC/RDP/SPICE-unavailable caveat noted above.
