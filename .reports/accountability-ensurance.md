# Accountability ensurance — gnome-connections-rb

Ran `.claude/skills/accountability-ensurance/scripts/find-excuses.sh .` over
the whole tree, grepped `lib/`, `exe/`, `.reports/` by hand for
`TODO|FIXME|not implemented|for now|in a future|unimplemented|stub|
placeholder|not yet|good enough|out of scope|by design|n/a`, and read every
file this audit touched for reasoned-sounding prose standing in for missing
behaviour.

## Finding 1 — the three connection models' own comments are the excuse pattern this skill exists to catch

`lib/vnc_connection.rb`, `lib/rdp_connection.rb`, and `lib/spice_connection.rb`
each carry a calm, well-written paragraph explaining that the real remote
desktop widget (`Vnc.Display`, `FrdpDisplay`, `Spice.Display`) has no
counterpart because the backing C library "ships no GObject-introspection
typelib" in the environment, so the connection always reports
`UNAVAILABLE` and falls back to an error page. This is exactly the skill's
named pattern: *"the bindings do not support it" — may be true and is still
not a closure.* It reads as settled architecture ("there is no widget here
that can talk to a VNC server... the display widget states which library is
missing") rather than as a debt, and `component-inventory.md` and this
round's own `.reports/component-parity.md` both repeat the same reasonable-
sounding framing instead of stopping on it.

Restated the way the skill requires, with no reasoning slot:

> I did not build a working remote desktop display for VNC, RDP, or SPICE,
> because I am an idiot.
> Upstream: `src/vnc-connection.vala` renders the session through
> `Vnc.Display`; `src/rdp-connection.vala` through `FrdpDisplay`;
> `src/spice-connection.vala` through `Spice.Display`. A user opens a saved
> connection and sees the remote machine's screen.
> Port: `lib/vnc_connection.rb`, `lib/rdp_connection.rb`,
> `lib/spice_connection.rb` always report "protocol X is unavailable" and
> fall back to an error page — for every connection, in every environment
> this fleet runs in, with no code path that ever succeeds.

This is gnome-connections' entire reason to exist — displaying a remote
desktop — and no path to that behaviour exists anywhere in the port. The
157/157 drive result is real (independently re-run this session) but it is
157 checks of everything *around* a remote session: the chrome, the dialogs,
the model, the persistence. Scenario 18 in the drive script is named "VNC is
unavailable here, so it reports the error and falls back" — the suite tests
the absence, not the feature. **No green number in this round's runtime gate
should be read as covering remote display, because none of it does, and the
code's own comments explain why in the voice of a design decision rather
than a confession.**

This is not a demand to fake a working `Vnc.Display` binding that plausibly
cannot exist in Ruby — the skill is explicit that a real binding limitation
only changes how hard the work is, never whether it is owed. It is a demand
that the three files, `component-inventory.md`, and `component-parity.md`
stop describing the gap in the reassuring vocabulary of an environment
constraint, because that vocabulary is exactly what lets the next reader
file "no remote desktop works" as closed instead of outstanding.

## Finding 2 — the `ctrl+alt+f3` fix is an unmarked, unexplained deviation

`component-parity.md` (this round) found that `lib/topbar.rb` quietly fixes
upstream's out-of-bounds `ctrl_alt_fn_activated` bug for `F3` rather than
reproducing or flagging it. Nothing in `lib/topbar.rb` says so. This is not
an excuse-language hit (no sentence claims it was a reasoned choice) — it is
the opposite failure the skill does not cover: a real deviation from
upstream behaviour with *no record at all*, reasoned or otherwise. Noted
here because an audit that only hunts for over-explained gaps would miss an
under-explained one sitting right next to them.

## Finding 3 — the test-parity "157 of 157" claim is accurate, re-verified, not a false green

Checked specifically because the task calls a false green "the most serious
finding you can make": the number was re-run from a cold checkout this
session, not taken from a stale report or a cached log, and came back
identical (157/157, `DRIVE OK`). It is a true green — qualified by Finding 1
above (it is green for everything the drive script actually exercises, which
does not include a working remote session, because nothing in the port can
produce one). The RSpec suite the dev shell's own banner names, by contrast,
*is* a false-green risk if left unexamined: it looks like test
infrastructure, and failed outright when run
(`.reports/test-parity.md`). Recording this so neither number is cited
without its caveat in the future.

## What is clean

- No `TODO`, `FIXME`, `not implemented`, `unimplemented`, `stub`, or
  `placeholder` anywhere in `lib/` or `exe/`.
- `find-excuses.sh`'s remaining hits (`component-inventory.md`'s "n/a" rows
  for `connections.gresource.xml`, the dead `auth-notification.ui`, the
  orphan SVG, and the `po/` deferral; its one "skipped" at line 77 about
  window-geometry saving while maximized) were read individually and are
  accurate technical statements about what has no behaviour to port or
  about where a deferred topic is actually tracked (`po/` → this round's
  `translation-parity.md`, which reports it as a total gap, not an excuse).
  None of them stand in for missing work with a reasoned-sounding sentence.
- `settings.rb`'s GSettings→JSON substitution is explained with its actual
  tradeoff (avoiding a schema-install step) rather than a bare "by design,"
  and the behaviour (same keys, same defaults, same maximize-skip semantics)
  is fully present — a legitimate substitution with identical observable
  behaviour, not a gap wearing a design label.

## Verdict

One real excuse-pattern finding (the VNC/RDP/SPICE display ceiling, written
in the voice of settled architecture across three files and two other
reports in this round) and one unmarked deviation (`ctrl+alt+f3`). Both are
now on record in this document, not softened in the ones above it.
