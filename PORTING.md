# Porting ledger — gnome-connections-rb

The contract this file keeps: every upstream unit on one side, the `lib/*.rb`
file that ports it on the other, updated whenever a file moves, splits or
gains a sibling. `.reports/` holds point-in-time audits of a given round;
this file is the thing those audits check against, not a replacement for it.

Upstream ref: `origin/master` (GTK3 + libhandy; `origin/gnome-50` carries an
identical `src/` file list). Never checked out or merged — read with
`git show origin/master:<path>` and ported from scratch into this `ruby`
branch, declaratively, per `.claude/skills/ruby-gtk`.

## File mapping (24 units)

| Upstream | Port | Notes |
|---|---|---|
| `src/main.vala`, `src/application.vala` | `lib/main.rb` | `App` is the single entry point; `exe/gnome-connections` is one expression on top of it. |
| `src/window.vala` | `lib/window.rb` | |
| `src/topbar.vala` | `lib/topbar.rb` | Deliberately fixes upstream's Ctrl+Alt+F3 out-of-bounds-array bug (`keyvals[3]` on a 3-element array) rather than reproducing it — documented in the file. |
| `src/collection-view.vala` | `lib/collection_view.rb` | |
| `src/collection-view-child.vala` | `lib/collection_view_child.rb` | |
| `src/actions-popover.vala` | `lib/actions_popover.rb` | |
| `src/assistant.vala` | `lib/assistant.rb` | |
| `src/display-view.vala` | `lib/display_view.rb` | |
| `src/notifications.vala` | `lib/notifications.rb` | |
| `src/dialogs.vala` | `lib/dialogs_window.rb` | |
| `src/onboarding-dialog.vala` | `lib/onboarding_dialog.rb` | |
| `src/onboarding-dialog-page.vala` | `lib/onboarding_dialog_page.rb` | |
| `src/preferences-widgets.vala` | `lib/preferences_widgets.rb` | |
| `src/vnc-preferences-window.vala` | `lib/vnc_preferences_window.rb` | |
| `src/rdp-preferences-window.vala` | `lib/rdp_preferences_window.rb` | |
| `src/spice-preferences-window.vala` | `lib/spice_preferences_window.rb` | |
| `src/connection.vala` | `lib/connection.rb` | Also defines `Credentials`, the file-backed stand-in for upstream's libsecret keyring entry (no libsecret typelib here either). |
| `src/vnc-connection.vala` | `lib/vnc_connection.rb` | Model/persistence/scale-mode behaviour is ported; the actual `Vnc.Display` widget has no counterpart (see "Known ceiling" below). |
| `src/rdp-connection.vala` | `lib/rdp_connection.rb` | Same ceiling; no `FrdpDisplay`. |
| `src/spice-connection.vala` | `lib/spice_connection.rb` | Same ceiling; no `Spice.Display`. `SpiceConnection.available?` is hardcoded `false`, matching upstream's `#if HAS_SPICE` build-time guard, since there is nothing to probe for in this environment. |
| `src/database.vala` | `lib/database.rb` | GKeyFile store, same path/format as upstream. |
| `src/ui/kbd-shortcuts-window.ui` | `lib/shortcuts_dialog.rb` | Standalone `.ui`, no `.vala` driver. |
| `src/ui/style.css` | `lib/style.rb` | Standalone CSS; GTK3→GTK4/Hdy→Adw colour-name rewrites noted inline (`@theme_bg_color` → `@window_bg_color`, etc). |
| `data/org.gnome.Connections.gschema.xml` | `lib/settings.rb` | JSON file under `XDG_CONFIG_HOME` in place of a compiled GSettings schema, so a checkout runs without an install step. Same two keys, same defaults. |

`lib/gnome_connections.rb` is the gem's require entry point (loads `main.rb`
under the gem's own name); `lib/gnome/connections/rb/version.rb` is the
gemspec's version file. Neither corresponds to an upstream unit.

## House shape

- `# frozen_string_literal: true`, then `require 'adwaita'` and
  `require_relative` for siblings, at the top of every file.
- Every class carries a comment naming the upstream file it was ported from.
- Widgets are built declaratively: memoized accessors, `.tap` blocks, no
  `return`, per `.claude/skills/ruby-gtk`.

## Known ceiling: no real remote-desktop rendering

`VncConnection`, `RdpConnection` and `SpiceConnection` port every piece of
upstream behaviour that is not the remote display itself — properties,
persistence, `.vnc`-file import, scale modes, the authentication/certificate
signal plumbing — but none of them can draw a remote desktop, because
`gtk-vnc`, `gtk-frdp` and `spice-gtk` ship no GObject-Introspection typelib
anywhere this fleet runs (checked this round: `find /nix/store -iname
'*vnc*.typelib' -o -iname '*frdp*.typelib' -o -iname '*spice*.typelib'` finds
none; the hits that do turn up are unrelated package hashes that happen to
contain the substring "vnc"). `connect_it` on every connection class reports
through `on_connection_error`, the same path upstream takes when a server
refuses a connection. See `FINDINGS.md` for the decision record on this gap.
