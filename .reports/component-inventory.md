# gnome-connections — upstream component inventory

Survey for the full-parity Ruby GTK4/Libadwaita port. No app code was written
in this step.

## Reading notes

- **The upstream ref is `origin/master`, not `origin/main`.** `origin/main`
  does not exist in this clone (`git ls-tree origin/main` → *Not a valid object
  name*). `origin/master` is the newest upstream branch (version `51.rc.1`,
  2026-09-01) and is the spec used below. `origin/gnome-50` carries the same
  source file list; `origin/gtk4-port` is an abandoned 2024 branch.
- **Upstream is GTK3 + libhandy**, not GTK4 + libadwaita: `meson.build` asks for
  `gtk+-3.0 >= 3.22` and `libhandy-1 >= 1.6.0`. Every `Hdy.*` below has to be
  ported to its `Adw.*` equivalent, and the GTK3-only widgets
  (`Gtk.EventBox`, `Gtk.RadioButton`, `Gtk.ComboBoxText`, `Gtk.ModelButton`,
  `Gtk.PopoverMenu` children, `Gtk.Bin`, `Gtk.ShortcutsWindow`,
  `size-allocate`/`key-press-event`/`configure-event`/`delete-event`/
  `button-release-event` signals) have no GTK4 counterpart and need the
  mappings noted per component.
- Upstream splits every component across a `.vala` class and a `src/ui/*.ui`
  GtkBuilder template; the two halves are unioned into one `lib/*.rb` per the
  `component-identification` skill.
- **Port status, re-checked on `ruby` at `b76ce03`:** every unit below now has
  a `lib/*.rb` file with real code (4,481 lines across 25 files), each opening
  with `# frozen_string_literal: true`, `require 'adwaita'` and a comment
  naming the upstream file it was ported from. The scaffold placeholder
  `lib/gnome_connections/application.rb` is gone; `lib/gnome_connections.rb`
  is now a five-line entry point that requires `lib/main.rb`. The per-unit
  presence column is the **Port status** table at the end of this file. What
  remains is parity *within* each unit, not missing units.
- Target paths follow the pilot port (`gnome-contacts-rb`): flat
  `lib/<thing>.rb`, snake_case, one upstream component per file.

## Components, in the order a user meets them

### lib/main.rb — the application: actions, About, CLI

Upstream: `src/main.vala`, `src/application.vala`

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Application` | 1 | — | `startup`, `activate`, `open`, `command_line`, `shutdown` | flags `HANDLES_COMMAND_LINE \| HANDLES_OPEN` |
| about dialog (`Gtk.show_about_dialog`) | 1 | — | `app.about` | authors, artists, translator-credits, GPL-3.0, comments "A remote desktop client for the GNOME desktop environment", `\xc2\xa9 2020 Red Hat, Inc.` → `Adw.AboutDialog` in the port |
| help (`Gtk.show_uri_on_window` → `help:gnome-connections`) | 1 | — | `app.help` | |
| — | | | `app.quit` → `quit_app` (hides every window) | |

App actions: `app.help`, `app.about`, `app.quit`. Holds the `GLib.ListStore` of
`Connection`s, the `GLib.Settings("org.gnome.Connections")`, the window list,
`first-run` onboarding trigger, `add_connection(uri)` /
`add_connection_from_file` (mime `application/x-vnc`), `remove_connection`
(undo notification), `load_connections`. CLI options: bare `URL to connect`,
`--file/-F PATH` ("Open .vnc or .rdp file at the given PATH"),
`--fullscreen/-f`. Error strings: "Too many command-line arguments specified.",
"Couldn't open file of unknown mime type %s". Dark-scheme forced via
`Hdy.StyleManager.color_scheme = PREFER_DARK`.

### lib/window.rb — the main window

Upstream: `src/window.vala`, `src/ui/window.ui`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.ApplicationWindow` (`ConnectionsWindow`) | 1 | `devel` (only when app id is `…Connections.Devel`) | `key-press-event`→`on_key_pressed`, `delete-event`→`on_delete_event`, `configure-event`→`on_configure_event` | title "Connections"; GTK4: `Gtk.EventControllerKey` + `close-request` + `notify::default-width/height` |
| `Topbar` (own class) | 1 | — | — | `child type="titlebar"` |
| `Gtk.Box` | 1 | — | — | |
| `Gtk.SearchBar` | 1 | — | — | second search bar in the window template besides the collection view's |
| `Gtk.Overlay` (`notification_overlay`) | 1 | — | — | |
| `NotificationsBar` (own class) | 1 | — | — | overlay child |
| `Gtk.Stack` | 1 | — | — | 4 children |
| `CollectionView` (own class) | 1 | — | — | stack child |
| `Hdy.StatusPage` (`empty_view`) | 1 | — | — | **empty state**: title "Welcome to Connections", `icon_name` set from the app id at runtime → `Adw.StatusPage` |
| `DisplayView` (own class) | 1 | — | — | stack child |
| `Gtk.Box` (`loading_view`) + `Gtk.Spinner` | 1 + 1 | — | — | stack child |

Behaviour: window-size restore/save from the `window-size` GSettings key
(100 ms debounce, skipped while maximized or fullscreen); CSS loaded from
`ui/style.css`; `topbar.search_button.active` ↔
`collection_view.search_bar.search_mode_enabled` bidirectional binding;
`search_button.visible = model.n_items > 0`; stack switches collection ↔ empty
on `items_changed`; owns the `DialogsWindow` (modal, transient);
`show_preferences_window` dispatches on connection class;
**keyboard shortcuts handled here**: `<Ctrl>f` search, `F11` fullscreen,
`<Ctrl>q` quit, `F1` help, `<Ctrl>n` → `topbar.assistant.popdown()`, else
forwarded to the search bar.

### lib/topbar.rb — the two header bars and the display menus

Upstream: `src/topbar.vala`, `src/ui/topbar.ui`

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Stack` (`ConnectionsTopbar`) | 1 | — | — | collection ↔ display toolbar |
| `Hdy.HeaderBar` (`collection_toolbar`) | 1 | `titlebar` | — | title "Connections" → `Adw.HeaderBar` |
| `Gtk.MenuButton` (`new_button`) | 1 | — | popover = `Assistant` | icon `list-add-symbolic`, a11y label |
| `Gtk.MenuButton` (`main_menu_button`) | 1 | — | menu `main_menu_model` | icon `open-menu-symbolic` |
| `Gtk.ToggleButton` (`search_button`) | 1 | `image-button` | bound to the search bar | icon `edit-find-symbolic`, starts invisible |
| `Gtk.HeaderBar` (`display_toolbar`) | 1 | `titlebar` | — | title = connection's visible name |
| `Gtk.Button` (`back_button`) | 1 | — | `clicked`→`back_button_clicked` | icon `go-previous-symbolic` |
| `Gtk.MenuButton` (`display_menu_button`) | 1 | — | menu `display_menu_model` | icon `view-more-symbolic` |
| `Gtk.Button` (`disconnect_button`) | 1 | — | `clicked`→`disconnect_button_clicked` | icon `system-shutdown-symbolic` |
| `Gtk.MenuButton` (`keys_menu_button`) | 1 | — | popover `keys_input_popover` | icon `input-keyboard-symbolic` |
| `Gtk.Button` (`fullscreen_button`) | 1 | — | `display.fullscreen` | icon `view-fullscreen-symbolic` |
| `Gtk.PopoverMenu` + `Gtk.ModelButton` | 1 + 6 | — | `key.ctrl+alt+*` | GTK3-only `ModelButton`s → menu model items in GTK4 |
| `Assistant` (own class) | 1 | — | — | top-level object in the template |

Menus (`main_menu_model`): "Keyboard Shortcuts" → `win.show-help-overlay`,
"Help" → `app.help`, "About Connections" → `app.about`.
(`display_menu_model`): "Take Screenshot" → `display.take_screenshot`,
"Properties" → `display.properties`.
Action groups: `display` (`take_screenshot`, `fullscreen`, `properties` — a
`Fullscreen` menu item is appended in code as well) and `key`
(`ctrl+alt+backspace`, `ctrl+alt+del`, `ctrl+alt+f1`, `ctrl+alt+f2`,
`ctrl+alt+f3`, `ctrl+alt+f7`, each sending keyvals to the connection).
Note the upstream `ctrl_alt_fn_activated` bug: the `f3` branch writes
`keyvals[3]` on a 3-element array.

### lib/collection_view.rb — the grid of saved connections

Upstream: `src/collection-view.vala`, `src/ui/collection-view.ui`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.ScrolledWindow` (`ConnectionsCollectionView`) | 1 | — | — | |
| `Gtk.Box` | 1 | `view` | — | |
| `Gtk.SearchBar` | 1 | — | — | |
| `Gtk.SearchEntry` | 1 | — | `search-changed`→`on_search_changed` | invalidates the filter |
| `Gtk.FlowBox` | 1 | — | `child-activated`→`on_child_activated`, `button-release-event`→`on_button_release_event` | GTK4: right-click via `Gtk.GestureClick` button 3 |
| `Gtk.FlowBoxChild` | repeater | — | — | one per model item, `halign START`, built by `create_child` |
| `ActionsPopover` (own class) | 1 | — | — | context menu, anchored to the child's thumbnail |

Filter: substring match of the search text against `connection.uri` **or**
`connection.display_name`.

### lib/collection_view_child.rb — one connection tile

Upstream: `src/collection-view-child.vala`, `src/ui/collection-view-child.ui`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Box` (`ConnectionsCollectionViewChild`) | 1 | — | — | |
| `Gtk.Image` (`thumbnail`) | 1 | `thumbnail` | `connection.show` → `update_thumbnail` | default icon `<app-id>-symbolic`; live thumbnail scaled to 180×134 on a 3 s timeout |
| `Gtk.Label` (`connection_name`) | 1 | — | `connection.notify["display-name"]` → `update_display_name` | |

### lib/actions_popover.rb — the tile context menu

Upstream: `src/actions-popover.vala` (no `.ui`; menu built in code)

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Popover` | 1 | — | `bind_model(menu)` | GTK4: `Gtk.PopoverMenu.new_from_model` |
| menu item "Delete" | 1 | — | `connection.delete` | → `Application.remove_connection` |
| menu item "Properties" | 1 | — | `connection.properties` | → `show_preferences_window` |

Action group `connection` with entries `delete`, `properties`.

### lib/assistant.rb — the "new connection" popover

Upstream: `src/assistant.vala`, `src/ui/assistant.ui`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Popover` (`ConnectionsAssistant`) | 1 | — | — | |
| `Gtk.Box` | 4 | — | — | |
| `Gtk.Label` | 2 | — | — | "Enter the network identifier of the remote desktop to connect to:", "Connection Type" (bold attribute) |
| `Gtk.Entry` (`url_entry`) | 1 | — | `changed`→`on_url_entry_changed`, `activate`→`on_url_entry_activated` | |
| `Gtk.RadioButton` (`rdp_radio_button`) | 1 | — | `toggled`→`on_url_entry_changed` | "RDP (Standard, high performance)" → GTK4 `Gtk.CheckButton` group |
| `Gtk.RadioButton` (`vnc_radio_button`) | 1 | — | `toggled`→`on_url_entry_changed` | "VNC (Legacy)" |
| `Gtk.RadioButton` (`spice_radio_button`) | 1 | — | `toggled`→`on_url_entry_changed` | "SPICE (Virtual machines)", visible only when built with SPICE |
| `Gtk.Button` (`help_button`) | 1 | — | `clicked`→`on_help_button_clicked` | "Help" → `help:gnome-connections/connect` |
| `Gtk.Button` (`create_button`) | 1 | `suggested-action` | `clicked`→`on_create_connection_button_clicked` | "Connect", sensitivity driven by URI validation |
| `Gtk.EntryCompletion` + `Gtk.ListStore` + `Gtk.SizeGroup` | 1 each | — | — | non-widget helpers; completion is GTK3-only |

Validation: schemes `rdp://`, `vnc://`, `spice://`; bare addresses get the
selected radio's scheme prefixed; parsed with libxml's `Xml.URI.parse`;
`create_button.sensitive = uri.server != null`.

### lib/display_view.rb — the remote display

Upstream: `src/display-view.vala`, `src/ui/display-view.ui`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Box` (`ConnectionsDisplayView`) | 1 | — | `size-allocate`→`on_size_allocate`, `motion_notify_event` override | GTK4: `size-allocate` is gone (use `notify::width/height` on a measure pass), motion via `Gtk.EventControllerMotion` |
| `Gtk.Stack` | 1 | — | — | pages `loading`, `display` |
| `Gtk.Box` + `Gtk.Spinner` | 1 + 1 | — | — | **loading state** |
| `Gtk.Overlay` | 1 | — | — | |
| `Gtk.Label` (`size_label`) | 1 | `app-notification` | — | "%d×%d", shown for 3 s on resize |
| `Gtk.Button` (`escape_fullscreen_button`) | 1 | `app-notification` | `clicked`→`on_escape_fullscreen_button_clicked` | icon `view-fullscreen-symbolic`; revealed when the pointer is above y<40 in fullscreen |
| `Gtk.ScrolledWindow` | 1 | — | — | |
| `Gtk.EventBox` (`event_box`) | 1 | — | `scroll-event`→`on_event_box_scroll_event`, `event`→`on_event_box_event` | **GTK3-only**; hosts the connection's display widget and forwards raw events + cursor |

### lib/notifications.rb — the in-window notification bar

Upstream: `src/notifications.vala`, `src/ui/notification.ui`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Bin` (`NotificationsBar`) | 1 | `transparent-bg` | — | GTK4: `Adw.Bin`; `valign START`, `halign CENTER`; max 5 notifications, default timeout 6 s |
| `Gtk.Revealer` (`ConnectionsNotification`) | repeater | — | `dismissed` signal | |
| `Gtk.Grid` | 1 | `app-notification` | — | |
| `Gtk.Label` (`message_label`) | 1 | — | — | |
| `Gtk.Button` (`ok_button`) | 1 | — | `clicked` → OK func | label supplied per notification ("Undo", "Open") |
| `Gtk.Button` (close) + `Gtk.Image` | 1 + 1 | `flat` | `clicked`→`dismiss` | icon `window-close` |

**Error state**: `display_for_error(message)` renders a message-only
notification — used for authentication failure ("Authentication failed: %s")
and connection errors. The port's natural equivalent is
`Adw.ToastOverlay`/`Adw.Toast`.

### lib/dialogs_window.rb — certificate and authentication dialog

Upstream: `src/dialogs.vala`, `src/ui/dialog.ui`

One `Hdy.Window` with a `content_stack` of three pages and a `header_stack` of
two button pages.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Hdy.Window` (`ConnectionsDialogsWindow`) | 1 | — | `key-press-event`→`on_key_pressed` (Escape cancels), `delete-event`→`hide_when_delete` | modal, transient for the main window; `valign START`, `halign CENTER` |
| `Hdy.HeaderBar` (`dialog_headerbar`) | 1 | `titlebar` | — | title "Open Connection"; hidden on the authentication page |
| `Gtk.Stack` (`header_stack`) | 1 | — | — | pages `verify-button-page`, `connect-button-page` |
| `Gtk.Button` (`verify_button`) | 1 | — | `clicked`→`verify_button_clicked_cb` | "Verify" |
| `Gtk.Button` (`connect_button`) | 1 | — | `clicked`→`connect_button_clicked_cb` | "Connect", sensitivity from the switch |
| `Gtk.Button` (`cancel_button`) | 1 | — | `clicked`→`cancel_connection` | "Cancel" |
| `Gtk.Stack` (`content_stack`) | 1 | — | — | pages `certificate-verification`, `certificate-change-verification`, `authentication` |
| **page 1** `Gtk.Grid` + 3 `Gtk.Label` | 1 + 3 | — | — | "Verify Fingerprint", the long first-connection text, the fingerprint value (formatted 4×8 groups) |
| `Gtk.Popover` (`rdp_help_popover`) + `Gtk.Label` | 1 + 1 | — | — | "On Windows run certlm.msc or certmgr.msc…" |
| `Gtk.MenuButton` (`help_button`) + `Gtk.Image` | 1 + 1 | `image-button` | — | icon `help-about-symbolic` |
| **page 2** `Gtk.Grid` + `Gtk.Image` + 2 `Gtk.Label` | 1+1+2 | — | — | "Unexpected Certificate" + mismatch text |
| `Hdy.PreferencesPage` / `Hdy.PreferencesGroup` / `Hdy.ActionRow` | 1/1/1 | — | — | row "Delete Local Certificate" |
| `Gtk.Switch` (`delete_local_certificate_switch`) | 1 | — | `notify::active`→`delete_local_certificate_switch_changed` | gates the Connect button |
| **page 3** `Gtk.Box` + `Hdy.WindowHandle` + `Gtk.Grid` | 1 each | — | — | |
| `Gtk.Label` | 2 | — | — | "Authentication Required" + "The remote server "%s" requires…" |
| `Hdy.PreferencesPage`/`Group` | 1/1 | — | — | |
| `Hdy.ActionRow` (`username_row`, `password_row`, `domain_row`) | 3 | — | — | shown per `need_username` / `need_password` / `need_domain` |
| `Gtk.Entry` (`username_entry`, `password_entry`, `domain_entry`) | 3 | — | `activate`→`authenticate_button_clicked`; `focus` handlers on all three | placeholders "Username…", "Password…", "Domain…" |
| `Gtk.Image` (`document-edit-symbolic`) | 3 | — | — | one per row |
| `Gtk.Button` (`show_password_button`) + `Gtk.Image` (`show_password_icon`) | 1 + 1 | `image-button` | `clicked`→`show_password_button_clicked` | icon toggles `view-reveal-symbolic` ↔ `user-not-tracked-symbolic` |
| `Gtk.Popover` (`domain_help_popover`) + `Gtk.Label` | 1 + 1 | — | — | "Domain field is commonly optional…" |
| `Gtk.MenuButton` (`help_domain_button`) + `Gtk.Image` | 1 + 1 | `image-button` | — | icon `help-about-symbolic` |
| `Gtk.Button` (`cancel_authentication_button`) | 1 | inline CSS `button#cancel_button {…}` | `clicked`→`cancel_authentication_clicked` | "Cancel" |
| `Gtk.Button` (`authenticate_authentication_button`) | 1 | `suggested-action`, inline `button#authenticate_button {…}` | `clicked`→`authenticate_button_clicked` | "Authenticate" |

Behaviour worth keeping: an explicit tab-order focus chain across the seven
authentication controls, a `Mutex` + 50 ms `check_show_flags` poll so the
connection threads can ask for a page, and `dismiss` clearing all three entries
and the switch.

### lib/onboarding_dialog.rb — first-run carousel

Upstream: `src/onboarding-dialog.vala`, `src/ui/onboarding-dialog.ui`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Hdy.Window` (`ConnectionsOnboardingDialog`) | 1 | `onboarding-dialog` | `delete-event`→`gtk_widget_hide_on_delete`, `key-press-event`→`on_key_pressed` (Escape closes) | transient for the main window; shown when `first-run` is true, which it then clears |
| `Gtk.Box` | 3 | — | — | incl. `indicator-spacer` |
| `Gtk.Overlay` | 1 | — | — | |
| `Hdy.Carousel` (`paginator`) | 1 | — | `notify::position`→`on_position_changed` | → `Adw.Carousel` |
| `OnboardingDialogPage` | 5 | — | — | see below |
| `Gtk.Button` (`go_back_button`) + `Gtk.Image` | 1 + 1 | `circular` | `clicked`→`on_back_button_clicked` | icon `go-previous-symbolic`, hidden on page 1 |
| `Gtk.Button` (`go_next_button`) + `Gtk.Image` | 1 + 1 | `circular` | `clicked`→`on_next_button_clicked` | icon `go-next-symbolic`, hidden on the last page |
| `Gtk.Button` (`close_button`) | 1 | — | `clicked`→destroy | label "_No Thanks" on page 1, "_Close" on the last, hidden in between |
| `Hdy.CarouselIndicatorDots` (`indicator`) | 1 | — | — | → `Adw.CarouselIndicatorDots` |
| `Gtk.SizeGroup` | 1 | — | — | non-widget |

### lib/onboarding_dialog_page.rb — one carousel page

Upstream: `src/onboarding-dialog-page.vala`, `src/ui/onboarding-dialog-page.ui`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Box` (`ConnectionsOnboardingDialogPage`) | 1 | `onboarding-dialog-page` | `map`→`load_css` | `image` property injects `background-image: url("resource://…")` through a per-instance `Gtk.CssProvider` |
| `Gtk.Label` (`title_label`) | 1 | `onboarding-dialog-page-title-label`, `title-1` | — | |
| `Gtk.Label` (`description_label`) | 1 | — | — | |

The five pages' copy and art: "Welcome to Connections" / welcome.svg;
"Access other desktops" / remote-computer.svg; "Connect to different operating
systems" / multiplatform.svg; "Setup is required" / configure-access.svg;
"Start by creating your first connection" / thankyou.svg.

### lib/preferences_widgets.rb — preferences base class and the switch row

Upstream: `src/preferences-widgets.vala`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Hdy.PreferencesWindow` (`PreferencesWindow`) | 1 | — | — | base class; transient for the main window; `bind_widget_property` does a bidirectional `connection`↔widget property binding plus an initial push → `Adw.PreferencesWindow`/`Adw.PreferencesDialog` |
| `Hdy.ActionRow` (`BooleanProperty`) | 1 | — | `active` property bound bidirectionally | holds a `Gtk.Switch` (`valign CENTER`) as its activatable widget → `Adw.SwitchRow` |
| `Gtk.Switch` | 1 | — | — | inside `BooleanProperty` |

### lib/vnc_preferences_window.rb — VNC connection preferences

Upstream: `src/vnc-preferences-window.vala`, `src/ui/vnc-preferences.ui`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `PreferencesWindow` subclass | 1 | — | — | title "Connection preferences" |
| `Hdy.PreferencesPage` | 1 | — | — | |
| `Hdy.PreferencesGroup` | 2 | — | — | second titled "Display" |
| `Hdy.ActionRow` | 4 | — | — | "Address", "Name", "Bandwidth", "Scale mode" |
| `Gtk.Label` (`host_address_label`) | 1 | — | bound to `uri` | |
| `Gtk.Entry` (`connection_name_entry`) | 1 | — | bound to `display_name` | |
| `BooleanProperty` | 3 | — | bound to `view-only`, `show-local-pointer`, `enable_audio` | "View only", "Show local pointer", "Enable audio" |
| `Gtk.ComboBoxText` (`bandwidth_combo`) | 1 | — | bound to `bandwidth` | items `high-quality` "High quality", `fast-refresh` "Fast refresh" → GTK4 `Adw.ComboRow` |
| `Gtk.ComboBoxText` (`scale_mode_combo`) | 1 | — | bound to `scale-mode` | items `resize-desktop` "Resize desktop", `fit-window` "Fit window", `original` "Original size" |

### lib/rdp_preferences_window.rb — RDP connection preferences

Upstream: `src/rdp-preferences-window.vala`, `src/ui/rdp-preferences.ui`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `PreferencesWindow` subclass | 1 | — | — | title "Connection preferences" |
| `Hdy.PreferencesPage` / `Group` | 1 / 1 | — | — | |
| `Hdy.ActionRow` | 2 | — | — | "Address", "Name" |
| `Gtk.Label` / `Gtk.Entry` | 1 / 1 | — | bound to `uri` / `display_name` | |
| `Gtk.ComboBoxText` (`scale_mode_combo`) | 1 | — | bound to `scale-mode`, `connection.notify["resize-supported"]`→`update_scale_mode_combo` | items `fit-window`, `original`; "Resize desktop" is **inserted dynamically** at index 0 when the server supports resize |

### lib/spice_preferences_window.rb — SPICE connection preferences

Upstream: `src/spice-preferences-window.vala`, `src/ui/spice-preferences.ui`

Same shape as VNC minus bandwidth/view-only: "Address", "Name",
`BooleanProperty` "Enable audio", `Hdy.ActionRow` "Scale mode" with a
three-item `Gtk.ComboBoxText`. Built only when SPICE is available
(`#if HAS_SPICE`), so the port should gate it the same way.

### lib/shortcuts_dialog.rb — keyboard shortcuts window

Upstream: `src/ui/kbd-shortcuts-window.ui` (standalone `.ui`, no backing
source; aliased in the GResource as `gtk/help-overlay.ui`, so GTK installs
`win.show-help-overlay` automatically)

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.ShortcutsWindow` (`help_overlay`) | 1 | — | `win.show-help-overlay` | → `Adw.ShortcutsDialog` in the port |
| `Gtk.ShortcutsSection` | 1 | — | — | |
| `Gtk.ShortcutsGroup` | 2 | — | — | "Overview", "Connection Display" |
| `Gtk.ShortcutsShortcut` | 5 | — | — | `F1` Help, `<Ctrl>f` Search, `<Ctrl>question`/`<Ctrl>F1` Keyboard Shortcuts, `<Ctrl>q` Quit, `F11` Fullscreen |

### lib/style.rb — the app stylesheet

Upstream: `src/ui/style.css`

Classes defined: `flash` (plus the `flash_animation` keyframes, 300 ms, used by
the screenshot flash in `connection.vala`), `thumbnail` (used by
`collection-view-child.ui`), `onboarding-dialog-page` (used by
`onboarding-dialog-page.ui`). `transparent-bg` (notifications bar),
`onboarding-dialog` and `onboarding-dialog-page-title-label` are **applied but
never defined** upstream — the first two rely on the theme, the third is dead.
The port loads the equivalent through a `Gtk::CssProvider` string.

## Non-widget components the UI depends on

These carry no widgets of their own but every component above is driven by
them, so they are port units too.

| Upstream file | Target | Kind | What it holds |
|---|---|---|---|
| `src/connection.vala` | `lib/connection.rb` | model (abstract base) | `show` signal, `uri`/`host`/`port`/`protocol`/`display_name`, libsecret credential storage, `take_screenshot` (file "Screenshot from %s", notification "Screenshot taken" + "Open", `flash` CSS pulse), certificate-verify and authentication hooks into `DialogsWindow`, auth-failure error text |
| `src/vnc-connection.vala` | `lib/vnc_connection.rb` | model + display widget | `Vnc.Display`, `view-only`, `show-local-pointer`, `enable_audio`, `bandwidth`, `scale_mode`, clipboard sync, `.vnc` file import ("VNC File is missing key "%s""), port 5900 |
| `src/rdp-connection.vala` | `lib/rdp_connection.rb` | model + display widget | `FrdpDisplay` (gtk-frdp subproject), `resize_supported`, `scale_mode`, cert-change callbacks, port 3389 |
| `src/spice-connection.vala` | `lib/spice_connection.rb` | model + display widget | `Spice.Display`/`Session`, `enable_audio`, `scale_mode`, port 3128; optional build |
| `src/database.vala` | `lib/database.rb` | persistence | GKeyFile-backed connection store: `get_connections`, `add_connection`, `delete_connection`, per-property save/load, `find_connection_by_uri` |
| `data/org.gnome.Connections.gschema.xml` | `lib/settings.rb` | settings | keys `first-run` (b, true) and `window-size` ((ii), (1024, 768)) |
| `src/connections.gresource.xml` | — | manifest | 23 resources: 13 `.ui`, 1 `.css`, 6 `.svg` (onboarding art + fingerprint2 icon). The port builds widgets in code, so only the SVG art and the CSS need a home |
| `po/` (55 locales, `po/LINGUAS`) + `po/POTFILES.in` (25 files) | — | translations | handled by the translation-parity step, not a `lib/*.rb` |

## Dead / orphan upstream components

| Upstream file | Status |
|---|---|
| `src/ui/auth-notification.ui` | `ConnectionsAuthNotification` template (`Gtk.Revealer` + `Gtk.Grid.app-notification`, labels "_Username"/"_Password", two `Gtk.Entry`s, "Sign In" `Gtk.Button`, handlers `on_username_entry_map`, `on_password_entry_map`, `on_username_entry_activated`, `on_password_entry_activated`, `on_auth_button_clicked`). Listed in the GResource and in `POTFILES.in`, but **no Vala class references it** — the in-window auth bar was replaced by the authentication page of `DialogsWindow`. Do not port; its strings still live in the catalogue. |
| `src/ui/fingerprint2-symbolic.svg` | In the GResource, referenced from no `.ui` or source file. |

## Totals

22 port units: 15 user-facing widget components, 1 stylesheet, 6 model /
persistence / settings units. Upstream carries 13 GtkBuilder templates
(12 class-backed + the shortcuts window), 3 action groups (`app`, `display`,
`key`) plus the per-tile `connection` group, 5 keyboard shortcuts in the
shortcuts window and 5 more handled directly in `on_key_pressed`, 2 menu models
with 5 items, 1 empty state, 1 loading state and 1 error path (the notification
bar).

## Port status

Re-checked against `lib/` on `ruby` at `b76ce03`. Every unit is present; the
remaining work is per-unit parity, which `component-parity` checks, not the
creation of new files.

| Upstream file(s) | Target | Kind | Present | Lines |
|---|---|---|---|---:|
| `src/main.vala`, `src/application.vala` | `lib/main.rb` | application (actions, About, CLI) | yes | 365 |
| `src/window.vala`, `src/ui/window.ui` | `lib/window.rb` | window | yes | 288 |
| `src/topbar.vala`, `src/ui/topbar.ui` | `lib/topbar.rb` | header bars + display menus | yes | 274 |
| `src/collection-view.vala`, `src/ui/collection-view.ui` | `lib/collection_view.rb` | page (grid of connections) | yes | 185 |
| `src/collection-view-child.vala`, `src/ui/collection-view-child.ui` | `lib/collection_view_child.rb` | tile / row | yes | 126 |
| `src/actions-popover.vala` | `lib/actions_popover.rb` | context menu | yes | 78 |
| `src/assistant.vala`, `src/ui/assistant.ui` | `lib/assistant.rb` | popover (new connection) | yes | 251 |
| `src/display-view.vala`, `src/ui/display-view.ui` | `lib/display_view.rb` | page (remote display) | yes | 217 |
| `src/notifications.vala`, `src/ui/notification.ui` | `lib/notifications.rb` | notification bar / error state | yes | 188 |
| `src/dialogs.vala`, `src/ui/dialog.ui` | `lib/dialogs_window.rb` | dialog (certificate + auth) | yes | 468 |
| `src/onboarding-dialog.vala`, `src/ui/onboarding-dialog.ui` | `lib/onboarding_dialog.rb` | dialog (first-run carousel) | yes | 225 |
| `src/onboarding-dialog-page.vala`, `src/ui/onboarding-dialog-page.ui` | `lib/onboarding_dialog_page.rb` | carousel page | yes | 79 |
| `src/preferences-widgets.vala` | `lib/preferences_widgets.rb` | preferences base + switch row | yes | 170 |
| `src/vnc-preferences-window.vala`, `src/ui/vnc-preferences.ui` | `lib/vnc_preferences_window.rb` | preferences window | yes | 70 |
| `src/rdp-preferences-window.vala`, `src/ui/rdp-preferences.ui` | `lib/rdp_preferences_window.rb` | preferences window | yes | 75 |
| `src/spice-preferences-window.vala`, `src/ui/spice-preferences.ui` | `lib/spice_preferences_window.rb` | preferences window | yes | 51 |
| `src/ui/kbd-shortcuts-window.ui` | `lib/shortcuts_dialog.rb` | shortcuts dialog | yes | 50 |
| `src/ui/style.css` | `lib/style.rb` | stylesheet | yes | 88 |
| `src/connection.vala` | `lib/connection.rb` | model (abstract base) | yes | 442 |
| `src/vnc-connection.vala` | `lib/vnc_connection.rb` | model + display widget | yes | 177 |
| `src/rdp-connection.vala` | `lib/rdp_connection.rb` | model + display widget | yes | 146 |
| `src/spice-connection.vala` | `lib/spice_connection.rb` | model + display widget | yes | 139 |
| `src/database.vala` | `lib/database.rb` | persistence | yes | 224 |
| `data/org.gnome.Connections.gschema.xml` | `lib/settings.rb` | settings | yes | 100 |
| `src/connections.gresource.xml` | — | manifest (SVG art + CSS only) | n/a | — |
| `po/` (55 locales) | — | translations (`translation-parity` step) | n/a | — |
| `src/ui/auth-notification.ui` | — | dead upstream template, not ported | n/a | — |
| `src/ui/fingerprint2-symbolic.svg` | — | orphan resource, not ported | n/a | — |
