# Component parity — gnome-connections-rb vs. origin/master

Adversarial spot-check across the units `component-inventory.md` lists,
reading both the upstream `.vala`/`.ui` and the port `lib/*.rb` side by side
for each, plus independent re-run of `test/drive_gnome_connections.rb`.

## Findings that hold up (sampled in depth)

- **`lib/actions_popover.rb`** vs `src/actions-popover.vala`: action group
  name (`connection`), both action names, both menu labels, and the
  update-for-item re-enable-and-rebind flow all match line for line.
- **`lib/main.rb`**'s About dialog: `COMMENTS`, `COPYRIGHT`
  (`© 2020 Red Hat, Inc.`), `AUTHORS` (Felipe Borges), `ARTISTS` (Jakub
  Steiner), `GPL_3_0`, `translator-credits` all match
  `src/application.vala`'s `Gtk.AboutDialog.with_parent` construction
  byte-for-byte on content.
- **`lib/settings.rb`**: upstream's two-key `org.gnome.Connections` GSettings
  schema (`first-run` bool default `true`, `window-size` `(ii)` default
  `(1024, 768)`) is reproduced key-for-key, default-for-default, with a
  documented and reasonable substitution (JSON file under `XDG_CONFIG_HOME`
  instead of a compiled GSettings schema, since requiring a schema install
  step before a checkout can run is a worse tradeoff). `remember` correctly
  skips the save while maximized *or* fullscreen, matching
  `save_window_geometry`.
- **`lib/style.rb`**: the `.flash`/`flash_animation` keyframe rule, the
  `.thumbnail` rule (with the GTK3→Adwaita colour name rewrite
  `@theme_bg_color`→`@window_bg_color` etc. correctly applied and noted),
  the `.onboarding-dialog-page` rule, and — easy to miss — the two
  `#authenticate_button`/`#cancel_button` border rules that upstream's
  `dialogs.vala` loads as a *second*, separate CSS provider are all present
  in the port's `CSS`/`DIALOG_CSS` split.
- **`lib/vnc_connection.rb`/`rdp_connection.rb`/`spice_connection.rb`**: the
  model-level behaviour (properties, persistence, `.vnc`-file import, the
  `DEFAULT_BANDWIDTH` typo-fix note, scale modes, default ports) is ported
  faithfully and the files are explicit, in their own header comments, that
  the actual display widgets (`Vnc.Display`, `FrdpDisplay`, `Spice.Display`)
  have no counterpart because `gtk-vnc`/`gtk-frdp`/`spice-gtk` ship no
  GObject-Introspection typelib anywhere in this fleet's dev environment.
  `SpiceConnection.available?` / the VNC and RDP `UNAVAILABLE` constants are
  hardcoded, not a runtime typelib probe — but there is nothing to probe for,
  since none of the three libraries are introspectable here regardless of
  host. **This is a real functional ceiling on the whole port — no protocol
  can actually display a remote desktop — but it is transparently documented
  in three separate file headers and exercised as the expected fallback path
  by the drive harness (`test/drive_gnome_connections.rb` scenario 18), not
  silently dropped or glossed over.** Flagged here so it is on record, not
  because it looks hidden.

## A real, if minor, behavioral deviation: the `ctrl+alt+f3` bug

`component-inventory.md` already calls out upstream's own bug: `topbar.vala`'s
`ctrl_alt_fn_activated` builds `uint[] keyvals = { Control_L, Alt_L, 0 }` (a
3-element array, valid indices 0–2) and the `f3` branch assigns
`keyvals[3] = Gdk.Key.F3` — one past the end. In Vala this is either an
out-of-bounds write or silently truncated depending on the array
implementation; in either case, **upstream's own Ctrl+Alt+F3 combination
never actually sends F3** (`keyvals[2]` stays `0`).

`lib/topbar.rb`'s `KEY_COMBINATIONS` instead lists
`'ctrl+alt+f3' => %w[Control_L Alt_L F3]` — the port's Ctrl+Alt+F3 **does**
send F3. The inventory flags the upstream bug's existence but the port
silently fixes it rather than reproducing it or noting the deviation inline.
This is almost certainly the right behavior to ship, but it is a real,
observable difference from upstream (a user pressing the Ctrl+Alt+F3 menu
item gets a working key combination in the port and a broken one upstream),
and it was not called out as a deliberate fix anywhere in `lib/topbar.rb`'s
comments or in the inventory's own notes beyond naming the bug. Minor, but
worth recording rather than letting "ported faithfully" quietly mean
"ported, except where upstream was obviously wrong."

## Verified against a live run, not just source reading

`test/drive_gnome_connections.rb` was re-run this session
(`nix develop --command xvfb-run -a ruby test/drive_gnome_connections.rb`) and
reproduced **157 of 157 checks, `DRIVE OK`**, independently confirming the
runtime gate figure given for this round across 50 scenarios spanning all 24
identified units (see `.reports/test-parity.md` for the scenario list). No
component in `component-inventory.md` is left unexercised by that run except
the genuine environment ceiling already noted above (no VNC/RDP/SPICE
backend to actually connect through).

## Verdict

No missing window, dialog, menu, action, or state found beyond what
`component-inventory.md` already tracks. The port is faithful at a level of
detail (down to reproducing a dead, upstream-only CSS class and a specific
`.vnc`-file trailing-space key bug on the *fix* side while documenting the
fix) that reads as deliberate, checked work rather than a confident
approximation. The two items above — the VNC/RDP/SPICE display ceiling and
the undocumented Ctrl+Alt+F3 fix — are the only parity notes this audit
found, and neither is hidden; both are now on record.
