# Component parity ledger — gnome-connections-rb

The 24-unit list below is `PORTING.md`'s file mapping, independently
re-derived from `origin/master`'s tree in `.reports/component-identification.md`
and confirmed there against `.reports/component-inventory.md`. This file adds
what neither of those had: a tag from every `test/drive_gnome_connections.rb`
`d.step` scenario to the unit(s) it exercises, so a unit's drive coverage can
be checked without re-deriving it from scratch each audit round.

## Unresolved count discrepancy: "21 components" vs. 24 units

A prior round's runtime gate reported "157 checks passed... covering 21
components." This audit's unit list (below, and in `PORTING.md`) is **24**.
The gate that produces "21" is not part of this repository — it is not
`rake drive`, `test/drive_gnome_connections.rb`, or anything else checked in
here — so this round cannot inspect its counting method directly. What this
round *can* do, and does below, is tag every drive scenario against the
24-unit list, so that whoever computes "21" can diff their list against this
one and name the 3-unit (or counting-convention) difference explicitly,
rather than the two figures being compared as bare numbers. Until that
happens, this stays flagged unresolved — it is not waved through as
presumably-fine.

## 24 units, tagged against drive-script coverage

| # | Unit (`lib/*.rb`) | Exercised by `d.step` scenarios |
|---|---|---|
| 1 | `main.rb` | 1 (launch), 41 (`add_connection_from_file`), 43 (`parse_arguments`), 44 (F1), 46 (about), 48 (shutdown), 49 (quit) |
| 2 | `window.rb` | 1, 5, 6, 8, 15, 18, 23, 28, 44, 45, 47 |
| 3 | `topbar.rb` | 8, 12, 22, 23, 24, 25, 26, 27 |
| 4 | `collection_view.rb` | 11, 14, 15, 16, 17 |
| 5 | `collection_view_child.rb` | 11, 16, 18 |
| 6 | `actions_popover.rb` | 29, 30 |
| 7 | `assistant.rb` | 8, 9, 10, 11, 12, 13, 14 |
| 8 | `display_view.rb` | 18, 21, 22, 24, 25, 28 |
| 9 | `notifications.rb` | 19, 20 |
| 10 | `dialogs_window.rb` | 34, 35, 36, 37, 39 |
| 11 | `onboarding_dialog.rb` | 1, 2, 3, 4, 5 |
| 12 | `onboarding_dialog_page.rb` | 3, 4 |
| 13 | `preferences_widgets.rb` | 31, 32, 33 |
| 14 | `vnc_preferences_window.rb` | 31 |
| 15 | `rdp_preferences_window.rb` | 32 |
| 16 | `spice_preferences_window.rb` | 33 |
| 17 | `connection.rb` | 11, 25, 27, 28, 30, 34, 38, 39, 48 |
| 18 | `vnc_connection.rb` | 11, 19, 40 |
| 19 | `rdp_connection.rb` | 14 |
| 20 | `spice_connection.rb` | 33 (preferences only — see ceiling below) |
| 21 | `database.rb` | 11, 30, 42 |
| 22 | `shortcuts_dialog.rb` | 44 |
| 23 | `style.rb` | 7 |
| 24 | `settings.rb` | 6, 47 |

Every one of the 24 units has at least one drive-script scenario against it;
this confirms `component-parity.md`'s claim that the 157/157 run spans all 24
identified units, independent of the unresolved "21" figure above. Step
numbers are this round's re-reading of `test/drive_gnome_connections.rb`'s
`d.step` call sites in source order (1-indexed); a scenario can tag more than
one unit when it drives an interaction between them (e.g. step 11 touches
`assistant.rb`, `connection.rb`, `vnc_connection.rb`, `database.rb`,
`collection_view.rb` and `collection_view_child.rb` in one flow).

## The one ceiling this tagging cannot paper over

Units 18–20 (`vnc_connection.rb`, `rdp_connection.rb`, `spice_connection.rb`)
are tagged "exercised," and they are — but only their model/persistence
behaviour. No scenario anywhere in the drive script, and no scenario that
could be written in this environment, drives an actual remote-desktop
session through any of them. See `FINDINGS.md`.
