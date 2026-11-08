# Component identification — audit note

**Re-verified this round**: `ls lib/*.rb` and the nested
`lib/gnome/connections/rb/version.rb` are unchanged in count and name since
the prior round's identification pass; only `spec/*_spec.rb` and
root-level `.md` ledgers were added. The 24-unit mapping below still holds
with no re-derivation needed beyond confirming no `lib/` file moved.

`.reports/component-inventory.md` (422 lines, dated to `ruby` at `b76ce03`)
already is the component-identification deliverable for this port, and it is
thorough: per-file widget/CSS/signal/action tables for all 15 user-facing
units plus the 6 model/persistence/settings units and the stylesheet, a
dead-component note (`auth-notification.ui`, `fingerprint2-symbolic.svg`), a
GTK3→GTK4/Hdy→Adw mapping note per widget that needs one, and a
reading-notes preamble correctly identifying that upstream's actual ref is
`origin/master` (GTK3 + libhandy), not `origin/main` (which does not exist in
this clone).

This audit re-derives the unit list independently to check that inventory
rather than trust it blindly, and finds it accurate:

## Independent re-derivation

```
git ls-tree -r --name-only origin/master | grep '^src/' | grep -v '\.ui$'
```
→ 18 `.vala` files + `config.vapi`. Each of the 17 app `.vala` files (minus
`config.vapi`, a build-generated header) maps to exactly one `lib/*.rb`:

| Upstream `.vala` | Port `lib/*.rb` | Found in inventory? |
|---|---|---|
| main.vala, application.vala | main.rb | yes |
| window.vala | window.rb | yes |
| topbar.vala | topbar.rb | yes |
| collection-view.vala | collection_view.rb | yes |
| collection-view-child.vala | collection_view_child.rb | yes |
| actions-popover.vala | actions_popover.rb | yes |
| assistant.vala | assistant.rb | yes |
| display-view.vala | display_view.rb | yes |
| notifications.vala | notifications.rb | yes |
| dialogs.vala | dialogs_window.rb | yes |
| onboarding-dialog.vala | onboarding_dialog.rb | yes |
| onboarding-dialog-page.vala | onboarding_dialog_page.rb | yes |
| preferences-widgets.vala | preferences_widgets.rb | yes |
| vnc-preferences-window.vala | vnc_preferences_window.rb | yes |
| rdp-preferences-window.vala | rdp_preferences_window.rb | yes |
| spice-preferences-window.vala | spice_preferences_window.rb | yes |
| connection.vala | connection.rb | yes |
| vnc-connection.vala | vnc_connection.rb | yes |
| rdp-connection.vala | rdp_connection.rb | yes |
| spice-connection.vala | spice_connection.rb | yes |
| database.vala | database.rb | yes |

Plus the two units with no backing `.vala` source, correctly caught by the
inventory's "standalone `.blp`/`.ui`" rule: `src/ui/kbd-shortcuts-window.ui`
→ `lib/shortcuts_dialog.rb`, and `src/ui/style.css` → `lib/style.rb`. Plus
`data/org.gnome.Connections.gschema.xml` → `lib/settings.rb`, correctly
identified as a non-widget unit upstream drives through GSettings.

**24 units identified upstream, 24 corresponding `lib/*.rb` files found.**
This matches the inventory's own count (its "22 port units" total groups
main+application as one row and folds the stylesheet/settings/database
differently, but the file-level mapping is identical; no file is missing
from either side's accounting).

## One thing the existing inventory's reading notes slightly overstate

It calls `origin/master` "the newest upstream branch." `git branch -a` on
this clone also lists `origin/gnome-50`, whose tree is byte-identical in file
*list* to `master` (same `src/` files) — the inventory does note this
("`origin/gnome-50` carries the same source file list"), so this is not a
correction, just confirmation that the claim holds under this session's own
check.

## Verdict

No additional components found beyond what `component-inventory.md` already
lists, and no listed component is spurious. Identification is sound; the
remaining question is parity *within* each identified unit, covered in
`.reports/component-parity.md`.
