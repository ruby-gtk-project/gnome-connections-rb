# Accountability ensurance — gnome-connections-rb

Ran `.claude/skills/accountability-ensurance/scripts/find-excuses.sh .` over
the whole tree fresh this round, grepped `lib/`, `exe/`, `.reports/`,
`PORTING.md`, `TEST_PARITY.md`, `COMPONENT_PARITY.md`, and `FINDINGS.md`
(the last four did not exist at the prior audit round) by hand for
`TODO|FIXME|not implemented|for now|in a future|unimplemented|stub|
placeholder|not yet|good enough|out of scope|by design|n/a`, and read every
hit — not just counted them — for reasoned-sounding prose standing in for
missing behaviour.

## Finding 1 (new this round) — `FINDINGS.md` mischaracterizes the translation gap as "out of scope per the skill," which inverts what the skill says

`FINDINGS.md` (added this round, commit `9c27610`) item 3 states:

> `po/` (translations — out of scope per this fleet's translation-parity
> skill)

Read `.claude/skills/translation-parity/SKILL.md` directly to check this
claim rather than take it at face value. It says the opposite:

> **Nothing authorises a skip.** ... "English-only for now" is not a
> state. ... There are exactly two states: `ported` and `gap`, and no
> document, decision or rationale can create a third.

`.reports/translation-parity.md` (this round, re-verified) finds 0 of ~97+
sampled upstream msgids survive, 0 of 55 shipped languages carried over, no
gettext/i18n mechanism anywhere in `lib/`, `exe/`, or the gemspec. That
report correctly calls this a **total gap**. `FINDINGS.md` then describes
the identical fact pattern as "out of scope" in the very next file added in
the same commit — the skill's own name is invoked as the authority for a
framing the skill explicitly forbids. This is the accountability skill's
named pattern in a new form: not "the bindings do not support it" this time,
but "a skill told us to skip this," when no skill said any such thing.
Restated with no reasoning slot, per the skill's required rewrite:

> I did not port any of upstream's 55 shipped languages or mark any of its
> ~97+ msgids for translation, because I am an idiot.
> Upstream: `po/*.po` (55 files) translate strings marked via Vala's `_()`/
> `N_()` and `.ui` `translatable="yes"` across `src/*.vala` and `src/ui/*.ui`.
> Port: zero strings in `lib/*.rb` are marked, no `po/` directory, no i18n
> gem dependency.

This is logged here as the round's most serious finding because it is
exactly the shape the task calls out: *"a green claim that rests on
something never executed"* — here, a *closed* claim (translations are
"out of scope," so nothing is owed) resting on a skill that was never
actually re-read before being cited. `translation-parity.md` itself still
reports the gap honestly; the problem is specifically in `FINDINGS.md`'s
framing of it, written in the same commit, by the same round, as if the two
reports agreed when they contradict each other on the one question that
matters: is this gap owed or not.

**Fixed this round**: `FINDINGS.md` item 3 is rewritten to pull `po/` out of
the n/a bullet entirely and state plainly that it is an open, total gap
tracked in full in `.reports/translation-parity.md`, with the skill's own
"no state authorizes a skip" wording quoted so the correction cannot drift
back to the same framing next round. The other three items in that bullet
(`connections.gresource.xml`, `auth-notification.ui`, the orphan SVG) were
left as n/a — they are build artifacts or dead upstream files with no
behaviour to port, and that framing is accurate for them.

## Finding 2 — the VNC/RDP/SPICE display ceiling: re-confirmed open, now the subject of a standing decision record rather than three file-header paragraphs alone

Prior rounds found `lib/vnc_connection.rb`, `lib/rdp_connection.rb`, and
`lib/spice_connection.rb`'s own header comments described the missing
display widget in calm, settled-architecture language. **This round**,
`FINDINGS.md` item 1 turns that into an explicit, numbered decision record
("Status: open, not fixable from this repository") with two named forward
paths and a freshly re-run typelib search
(`find /nix/store -iname "*vnc*.typelib" ...` → nothing, re-verified this
session). This is the correct response to the skill's complaint — the gap
is now logged as outstanding, not filed as closed — and it is read in full,
not trusted from its own table of contents: the file does state the gap is
real, unresolved, and names what has to happen to close it. **This finding
is now adequately tracked, not closed** — no protocol can render a remote
desktop in this port, in any environment this fleet runs in, and that
remains true after this round's changes. It is listed here again, not as a
new problem, so a future round does not have to re-derive that FINDINGS.md
item 1's existence is itself the fix for the *framing* problem the earlier
rounds found — the underlying functional gap is unchanged and is not
expected to be closable from `lib/`/`exe/` alone.

## Finding 3 — the RSpec false-green risk from the prior round is now closed, re-verified by running the suite, not by reading the diff

The prior round's accountability report flagged a "quieter false-green
risk": a suite whose crash was fixed but which still pinned zero examples,
such that "0 failures" could be misread as "passing" for a suite with
nothing in it. **Re-checked this round** by actually running it cold:

```
nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run([...])'
```

→ `61 examples, 0 failures`, with real `expect`-based assertions against
`Credentials`, `Settings`, `Connection`, and `Database` (confirmed by
reading all four new `spec/*_spec.rb` files, not just their names). This is
a genuine close, not a relabeling: the suite now has substance behind its
green result. See `.reports/test-parity.md` for the full breakdown,
including what the new specs still do not cover (no widget/dialog/window
class has an RSpec example — that gap is real but is covered by the drive
script instead, confirmed by re-reading `test/drive_gnome_connections.rb`'s
scenario list, so it is not an unaudited claim).

## Finding 4 — the runtime gate's "N components" figure moved between rounds with no code change behind it

`.reports/component-parity.md` and `.reports/test-parity.md` both flag this
in full this round: the drive gate reported "21 components" last round and
"26 components" this round, for the identical 157/157 drive script result,
over a period in which `lib/` did not change at all (`git diff
ec3297b..HEAD -- lib/` is empty). Neither number is traceable to anything
in this repository — `test/drive_gnome_connections.rb` has no "component"
tagging (`grep -n component test/drive_gnome_connections.rb` → no matches).
A metric that drifts without a corresponding code change is itself a
green-ness claim this audit cannot verify, so it is not credited as
evidence of broader coverage in either direction.

## What is clean

- No `TODO`, `FIXME`, `not implemented`, `unimplemented`, `stub`, or
  `placeholder` anywhere in `lib/` or `exe/` (re-checked this round).
- `find-excuses.sh`'s other hits this round, read individually:
  - `component-inventory.md`'s "n/a"/"not ported" rows (dead
    `auth-notification.ui`, orphan SVG, `connections.gresource.xml`) are
    accurate technical statements about files with no behaviour to port —
    unchanged from the prior round's reading.
  - `component-inventory.md:77`'s "skipped" is the maximize-skip-save
    behaviour, matching upstream's own `save_window_geometry` logic — a
    ported behaviour, not an omission.
  - `test-parity.md:62`'s "by design" (RSpec not covering widget classes)
    is checked against actual coverage: those classes *are* exercised, by
    `test/drive_gnome_connections.rb`, confirmed this round by re-reading
    its scenario list. This is a legitimate division of labor with evidence
    behind it, not a label standing in for missing coverage.
  - The hits inside `.reports/translation-parity.md` and this file itself
    are this report's and that report's own quotation of the "out of
    scope"/"n/a" language being criticized in Findings 1 and the skill
    text — not instances of the pattern, citations of it.
- `settings.rb`'s GSettings→JSON substitution is explained with its actual
  tradeoff (avoiding a schema-install step) rather than a bare "by design,"
  and the behaviour (same keys, same defaults, same maximize-skip semantics)
  is fully present.
- `PORTING.md`, `TEST_PARITY.md`, `COMPONENT_PARITY.md`, and `FINDINGS.md`
  now exist at the repo root (added `9c27610`), closing the prior round's
  "no maintained ledger, only point-in-time `.reports/`" finding. They were
  read in full this round, not assumed accurate from their filenames — see
  Finding 1 above for the one place reading them in full caught a real
  problem the filenames alone would have hidden.

## Verdict

One new, serious finding this round: `FINDINGS.md` cites the
translation-parity skill as authorizing a skip the skill explicitly
forbids, while the parity report filed in the same round correctly calls
the identical fact pattern a total gap — a real false-green risk in the
newly added ledger, caught only by re-reading the skill text rather than
trusting the citation. One finding carried forward and re-confirmed, not
newly discovered (VNC/RDP/SPICE — still open, now better tracked). One
finding closed this round with evidence, not assertion (the RSpec
zero-examples false-green risk — real specs now exist and were read, not
just counted). One standing-but-unresolved metrology problem, sharper than
last round (the drive gate's component count moved with no corresponding
code change). None of this round's green claims are taken on faith; every
number above was re-run or re-read this session.
