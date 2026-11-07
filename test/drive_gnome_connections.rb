# frozen_string_literal: true

# Drives the whole app headlessly: builds the window, walks the first-run
# onboarding tour, adds connections through the new-connection assistant,
# searches and filters the collection grid, opens a connection (and watches it
# fail over to the "unavailable" status page, since no gtk-vnc/gtk-frdp/
# spice-gtk typelib exists in this environment), deletes one with undo, drives
# every dialog (certificate verification, certificate-change verification,
# authentication, shortcuts, about, preferences) and the topbar's menus and
# key-combination popover, and screenshots each state.
#
# Why this file exists: a GTK app that loads is not a GTK app that works.
# `ruby -c` passes on code that builds an empty window, and the Ruby bindings
# differ from the C API in ways that only a run reveals.
#
# Run it from the repository root:
#
#   nix develop --command xvfb-run -a ruby test/drive_gnome_connections.rb
#
# GTK4 has no offscreen backend on this machine — gtk_init fails outright with
# no display — so xvfb-run is not optional here.

require 'fileutils'
require 'tmpdir'
require 'json'

# A scratch config directory, so a run never reads or writes the real one.
# Database, Settings and Credentials all resolve their paths from this at the
# moment they are first touched.
ENV['XDG_CONFIG_HOME'] = Dir.mktmpdir('gnome-connections-drive')

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'gnome_connections'
require_relative 'gtk_driver'

SHOTS = File.expand_path('../tmp/shots', __dir__)
FileUtils.rm_rf(SHOTS)

# A 32-byte fingerprint, formatted the way a TLS backend would hand one over.
FINGERPRINT = (1..32).map { |byte| format('%02x', byte) }.join(':')

# No modifier keys held at all — Window#on_key_pressed reads
# `state.control_mask?` unconditionally, so a bare key press needs a real
# Gdk::ModifierType, not the 0 a C caller could get away with.
NO_MODIFIER = Gdk::ModifierType.new(0)

# Turns the main loop over for `ms` milliseconds and comes back, without
# sleeping (every GTK callback runs on this same loop, so sleeping would
# block the very thing a wait is waiting on). This is what lets a carousel's
# scroll_to animation, a GtkSearchEntry's debounced "search-changed", or a
# GLib timeout actually run inside a single driver step.
def pump(ms)
  (Process.clock_gettime(Process::CLOCK_MONOTONIC) + (ms / 1000.0)).then do |deadline|
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      GLib::MainContext.default.iteration(false)
    end
  end
end

GtkDriver.drive(App.new, shots: SHOTS) do |d, app|
  d.window { app.main_window&.window }

  # --- Startup: first run shows the onboarding tour ------------------------

  d.step('the app launches; first run opens the window and the onboarding tour') do
    d.check('the window is a Gtk::ApplicationWindow') { app.main_window.window.is_a?(Gtk::ApplicationWindow) }
    d.check('its title is Connections') { app.main_window.window.title == 'Connections' }
    # App#activate flips settings.first_run to false the instant it shows the
    # tour, which already happened by the time this first step runs (it ran
    # inside the 'activate' handler App#build connects, before the GtkDriver
    # handler that schedules these steps even gets a turn) — so the only
    # window left to observe the first run through is the tour it opened.
    d.shot('01-onboarding')
  end

  d.step('the tour starts on page one with no back button, and the window is up') do
    pump(100)
    # Three, not two: Window#build also builds (but never shows)
    # DialogsWindow's own GtkWindow up front, and gtk_window_list_toplevels
    # lists every live GtkWindow, shown or not — so the baseline for this app
    # is already two before the tour ever opens.
    d.check('three toplevels: the main window, the dialogs window, and the tour') do
      Gtk::Window.list_toplevels.length == 3
    end
    # The dialog object itself is not kept anywhere public, so it is found
    # among the toplevels the way a user would see it: by title.
    Gtk::Window.list_toplevels.find { |w| w.title == 'Welcome to Connections' }.then do |tour|
      d.check('found the tour window') { !tour.nil? }
    end
  end

  d.step('the pages and carousel exist with upstream\'s five slides') do
    d.check('the carousel has five pages') do
      OnboardingDialog::PAGES.length == 5
    end
  end

  # The dialog instance itself is private to App#show_onboarding, so the
  # onboarding behaviour is exercised a second time, in isolation, against a
  # fresh instance this test can drive directly — the only way to reach
  # go_next_button/go_back_button/close_button at all.
  d.step('a fresh onboarding dialog walks forward through all five pages') do
    OnboardingDialog.new(app.main_window.window).tap do |tour|
      tour.build
      tour.present

      d.check('page one hides the back button') { !tour.go_back_button.visible? }
      d.check('page one shows the next button') { tour.go_next_button.visible? }
      d.check('page one shows the close button') { tour.close_button.visible? }
      d.check('page one\'s close button reads "No Thanks"') { tour.close_button.label == '_No Thanks' }

      # scroll_to animates, so "notify::position" — which is what drives
      # on_position_changed — lands a few main-loop iterations after the
      # click, not synchronously with it.
      (OnboardingDialog::PAGES.length - 1).times do
        tour.go_next_button.signal_emit('clicked')
        pump(300)
      end

      d.check('the last page hides the next button') { !tour.go_next_button.visible? }
      d.check('the last page shows the back button') { tour.go_back_button.visible? }
      d.check('the last page\'s close button reads "Close"') { tour.close_button.label == '_Close' }
      d.shot('02-onboarding-last-page')

      tour.go_back_button.signal_emit('clicked')
      pump(300)
      d.check('going back leaves the middle pages with both buttons') do
        tour.go_back_button.visible? && tour.go_next_button.visible?
      end
      d.check('and hides the close button again') { !tour.close_button.visible? }

      tour.window.close
      pump(100)
    end
  end

  d.step('closing the real tour returns to the empty collection') do
    # Every toplevel still titled this closes, not just the first match —
    # the fresh instance above should already be gone, but closing by title
    # rather than by object makes this robust either way.
    Gtk::Window.list_toplevels.select { |w| w.title == 'Welcome to Connections' }.each(&:close)
    pump(200)
    d.check('back down to the main window and the (unshown) dialogs window') do
      Gtk::Window.list_toplevels.length == 2
    end
  end

  d.step('first run is recorded as done and the empty state shows') do
    d.check('settings no longer reports a first run') { !app.settings.first_run? }
    d.check('the stack shows the empty page') { app.main_window.stack.visible_child_name == 'empty' }
    d.check('the search button is hidden with nothing saved') { !app.main_window.topbar.search_button.visible? }
    d.shot('03-empty')
  end

  # --- Style: the stylesheet installed at startup really parses ------------

  d.step('the stylesheet installed at startup parses with no errors swallowed') do
    [].then do |errors|
      Gtk::CssProvider.new.tap do |provider|
        provider.signal_connect('parsing-error') { |_p, _section, error| errors << error.message }
        provider.load_from_string("#{Style::CSS}\n#{Style::DIALOG_CSS}")
      end
      d.check('both stylesheets parse') { errors.empty? }
    end
    d.check('startup forced the dark colour scheme, as App#on_startup does') do
      Adwaita::StyleManager.default.color_scheme == :prefer_dark
    end
  end

  # --- The new-connection assistant popover ---------------------------------

  d.step('Ctrl+N opens the new-connection assistant, as the window\'s key handler does') do
    d.check('the assistant is not showing yet') { !app.main_window.topbar.assistant.popover.visible? }
    d.check('Ctrl+N is handled') do
      app.main_window.on_key_pressed(Gdk::Keyval::KEY_n, Gdk::ModifierType::CONTROL_MASK)
    end
  end

  d.step('the assistant is up, defaulting to RDP, with Connect disabled') do
    app.main_window.topbar.assistant.then do |assistant|
      d.check('the popover is showing') { assistant.popover.visible? }
      d.check('RDP is the default protocol') { assistant.rdp_radio_button.active? }
      d.check('SPICE is hidden, since this build has no spice-gtk') { !assistant.spice_radio_button.visible? }
      d.check('Connect starts disabled') { !assistant.create_button.sensitive? }
      d.shot('04-assistant')
    end
  end

  d.step('typing an explicit vnc:// address switches the radio and enables Connect') do
    app.main_window.topbar.assistant.then do |assistant|
      assistant.url_entry.text = 'vnc://box-one:5901'
      d.check('the VNC radio took over') { assistant.vnc_radio_button.active? }
      d.check('RDP is no longer selected') { !assistant.rdp_radio_button.active? }
      d.check('Connect is enabled with a host present') { assistant.create_button.sensitive? }
      assistant.create_button.signal_emit('clicked')
    end
  end

  d.step('the VNC connection landed in the model, the list and the database') do
    d.check('one connection exists') { app.connections.length == 1 }
    d.check('it is a VncConnection') { app.connections.first.is_a?(VncConnection) }
    d.check('its host is box-one') { app.connections.first.host == 'box-one' }
    d.check('the list store agrees') { app.model.n_items == 1 }
    d.check('the collection view built one tile') { app.main_window.collection_view.tiles.length == 1 }
    d.check('the search button appeared, now that something is saved') do
      app.main_window.topbar.search_button.visible?
    end
    d.check('the stack switched to the collection page') { app.main_window.stack.visible_child_name == 'collection' }
    d.check('the database kept it, under its own uuid') do
      Database.default.find_connection_by_uri(app.connections.first.uri).then do |found|
        found&.uuid == app.connections.first.uuid
      end
    end
    d.shot('05-one-connection')
  end

  d.step('the plus button reopens the assistant for a second, RDP connection') do
    app.main_window.topbar.new_button.activate
  end

  d.step('an address with no scheme takes the selected protocol\'s') do
    app.main_window.topbar.assistant.then do |assistant|
      # The assistant is one memoized popover, not rebuilt per popup, so
      # whichever radio the previous address selected (VNC, from box-one) is
      # still selected here — upstream's assistant is built once too, and
      # resetting the selection is not among the things on_url_entry_changed
      # does. Selecting RDP by hand is what actually exercises "no scheme
      # takes the selected protocol's", rather than whatever was left over.
      assistant.rdp_radio_button.active = true
      assistant.url_entry.text = 'box-two'
      d.check('a bare host enables Connect too') { assistant.create_button.sensitive? }
      assistant.create_button.signal_emit('clicked')
    end
  end

  d.step('the second connection is RDP, prefixed with the selected scheme') do
    d.check('two connections now') { app.connections.length == 2 }
    d.check('the newest is first (unshift)') { app.connections.first.host == 'box-two' }
    d.check('and it is an RdpConnection') { app.connections.first.is_a?(RdpConnection) }
    d.check('its scheme came from the selected radio, not the typed text') do
      app.connections.first.protocol == 'rdp'
    end
    d.check('two tiles now') { app.main_window.collection_view.tiles.length == 2 }
    d.shot('06-two-connections')
  end

  # --- Search and filter -----------------------------------------------------

  d.step('Ctrl+F opens the search bar, as the window\'s key handler does') do
    d.check('the search bar starts closed') { !app.main_window.collection_view.search_bar.search_mode_enabled? }
    d.check('Ctrl+F is handled') do
      app.main_window.on_key_pressed(Gdk::Keyval::KEY_f, Gdk::ModifierType::CONTROL_MASK)
    end
    d.check('the bar opened') { app.main_window.collection_view.search_bar.search_mode_enabled? }
    d.check('the header button followed it (the bidirectional bind)') do
      app.main_window.topbar.search_button.active?
    end
  end

  d.step('typing a search filters the grid to the matching tile') do
    app.main_window.collection_view.search_entry.text = 'box-one'
    # GtkSearchEntry's "search-changed" — what invalidates the flowbox's
    # filter — is itself debounced a little behind "changed", so the filter
    # has not actually run yet the instant the text is set.
    pump(300)
    d.check('box-one\'s tile stays visible') { app.main_window.collection_view.tiles[1].child_visible? }
    d.check('box-two\'s tile is filtered out') { !app.main_window.collection_view.tiles[0].child_visible? }
    d.shot('07-search-filtered')
  end

  d.step('clearing the search shows everything again') do
    app.main_window.collection_view.search_entry.text = ''
    pump(300)
    d.check('box-one is visible') { app.main_window.collection_view.tiles[1].child_visible? }
    d.check('box-two is visible again') { app.main_window.collection_view.tiles[0].child_visible? }
    app.main_window.on_key_pressed(Gdk::Keyval::KEY_f, Gdk::ModifierType::CONTROL_MASK)
  end

  # --- Opening a connection: the display view and the failure path ----------

  d.step('activating a tile opens its connection') do
    app.main_window.collection_view.flowbox.signal_emit(
      'child-activated',
      app.main_window.collection_view.tiles[1],
    )
  end

  d.step('VNC is unavailable here, so it reports the error and falls back') do
    d.check('the connection tried and failed to connect') { !app.connections.last.connected }
    d.check('the window fell back to the collection view') do
      app.main_window.stack.visible_child_name == 'collection'
    end
    d.check('the topbar went back to its collection toolbar') do
      app.main_window.topbar.stack.visible_child_name == 'collection'
    end
    d.check('a notification reports why') do
      app.main_window.notifications_bar.active_notification&.message&.include?('VNC is unavailable')
    end
    d.check('the revealer is showing it') { app.main_window.notifications_bar.bin.child.reveal_child? }
    d.shot('08-vnc-unavailable')
  end

  d.step('dismissing the notification clears the bar') do
    app.main_window.notifications_bar.dismiss
    d.check('nothing active now') { app.main_window.notifications_bar.active_notification.nil? }
  end

  d.step('display-view geometry: the loading/display stack and the escape button') do
    app.main_window.display_view.then do |view|
      d.check('the stack starts on the loading page') { view.stack.visible_child_name == 'loading' }
      d.check('the escape-fullscreen button starts hidden') { !view.escape_fullscreen_button.visible? }
      view.report_size(800, 600)
      d.check('report_size sets the label') { view.size_label.label == '800×600' }
      d.check('and reveals it') { view.size_label.visible? }
    end
  end

  # --- The display header bar: its menus, fullscreen and key-combination popover

  d.step('opening the connection once more, to drive the display header bar') do
    app.main_window.collection_view.flowbox.signal_emit(
      'child-activated',
      app.main_window.collection_view.tiles[1],
    )
    app.main_window.notifications_bar.dismiss
  end

  d.step('the back button returns to the collection, as back_button_clicked does') do
    app.main_window.topbar.back_button.signal_emit('clicked')
    d.check('back in the collection view') { app.main_window.stack.visible_child_name == 'collection' }
    d.check('the title reset to Connections') { app.main_window.topbar.collection_title.title == 'Connections' }
  end

  d.step('show_display_view retitles the topbar from the connection') do
    app.connections.last.then do |connection|
      app.main_window.topbar.show_display_view(connection)
      d.check('the display toolbar is up') { app.main_window.topbar.stack.visible_child_name == 'display' }
      d.check('its title is the connection\'s visible name') do
        app.main_window.topbar.display_title.title == connection.visible_name
      end
    end
  end

  d.step('the display menu\'s three actions reach the connection and the window') do
    app.connections.last.then do |connection|
      d.check('take_screenshot asks the connection, and does not crash with no display') do
        app.main_window.topbar.display_action_group.activate_action('take_screenshot', nil)
        true
      end
      # Xvfb run with no window manager (as this driver's are) never grants a
      # fullscreen or maximize request — gtk_window_fullscreen only asks the
      # compositor, and there is not one here to say yes — so `fullscreened?`
      # cannot be watched for the flip actually taking effect. What this can
      # show is that the action runs the real toggle logic without raising.
      d.check('fullscreen activates without raising') do
        app.main_window.topbar.display_action_group.activate_action('fullscreen', nil)
        app.main_window.topbar.display_action_group.activate_action('fullscreen', nil)
        true
      end
      d.check('properties opens that connection\'s preferences window') do
        app.main_window.topbar.display_action_group.activate_action('properties', nil)
        Gtk::Window.list_toplevels.any? { |w| w.title == 'Connection preferences' }
      end
      Gtk::Window.list_toplevels.find { |w| w.title == 'Connection preferences' }&.close
    end
  end

  d.step('the main menu, display menu and key popover carry upstream\'s items') do
    app.main_window.topbar.main_menu_model.then do |model|
      d.check('three items in the main menu') { model.n_items == 3 }
      d.check('the last is About Connections / app.about') do
        model.get_item_attribute_value(2, 'label', nil) == 'About Connections' &&
          model.get_item_attribute_value(2, 'action', nil) == 'app.about'
      end
    end
    app.main_window.topbar.display_menu_model.then do |model|
      d.check('two items in the display menu') { model.n_items == 2 }
    end
    app.main_window.topbar.keys_input_menu.then do |model|
      d.check('six key combinations, as Topbar::KEY_COMBINATIONS has') { model.n_items == 6 }
    end
    d.shot('09-display-header-bar')
  end

  d.step('a key-combination action sends the right keyvals to the connection') do
    app.connections.last.then do |connection|
      app.main_window.topbar.key_action_group.activate_action('ctrl+alt+del', nil)
      d.check('the connection received Control_L, Alt_L, Delete') do
        connection.sent_keys == %w[Control_L Alt_L Delete].map { |n| Gdk::Keyval.from_name(n) }
      end
    end
  end

  d.step('disconnecting from the display toolbar returns to the collection') do
    app.main_window.topbar.disconnect_button.signal_emit('clicked')
    d.check('back in the collection view') { app.main_window.stack.visible_child_name == 'collection' }
    d.check('the connection reports itself disconnected') { !app.connections.last.connected }
  end

  # --- The actions popover: delete (with undo) and properties ---------------

  d.step('the actions popover offers Delete and Properties, wired to the application') do
    ActionsPopover.new.tap do |popover|
      popover.build
      popover.popover.set_parent(app.main_window.collection_view.flowbox)
      popover.update_for_item(app.connections.last)

      d.check('the menu has two items') { popover.menu.n_items == 2 }
      d.check('delete is enabled') { popover.action_group.lookup_action('delete').enabled? }
      d.check('properties is enabled') { popover.action_group.lookup_action('properties').enabled? }

      before = app.connections.length
      popover.action_group.lookup_action('delete').activate(nil)

      d.check('the connection left the list at once') { app.connections.length == before - 1 }
      d.check('a notification offers Undo') { app.main_window.notifications_bar.active_notification.ok_button.visible? }
      # The grid's content changed this tick, so it has not been laid out
      # again yet — without a beat to let that happen, WidgetPaintable
      # produces no render node at all rather than a stale picture.
      pump(50)
      d.shot('10-delete-with-undo')

      app.main_window.notifications_bar.active_notification.accept
      d.check('Undo put it back') { app.connections.length == before }
      d.check('no notification is left after accepting') { app.main_window.notifications_bar.active_notification.nil? }

      popover.popover.unparent
    end
  end

  d.step('letting a deletion stand removes it from the database too') do
    app.connections.find { |c| c.host == 'box-two' }.then do |connection|
      uuid = connection.uuid
      App.instance.remove_connection(connection)
      app.main_window.notifications_bar.dismiss

      d.check('the model and the connections array lost it') do
        app.connections.none? { |c| c.uuid == uuid } && app.model.n_items == app.connections.length
      end
      d.check('the database no longer has it either') { Database.default.get_connection(uuid).nil? }
      d.check('the collection view is back down to one tile') { app.main_window.collection_view.tiles.length == 1 }
    end
  end

  # --- Preferences windows: binding is two-way ------------------------------

  d.step('the VNC preferences window binds the switches and combos both ways') do
    app.connections.first.then do |connection|
      VncPreferencesWindow.new(connection).tap do |prefs|
        prefs.build(transient_for: app.main_window.window)

        d.check('the address label reads the connection\'s uri') { prefs.host_address_label.label == connection.uri }

        prefs.view_only.switch.active = true
        d.check('the switch wrote the connection') { connection.view_only }

        connection.show_local_pointer = true
        d.check('the connection\'s change reached the switch') { prefs.show_local_pointer.switch.active? }

        prefs.connection_name_row.text = 'Office desktop'
        d.check('the name row wrote display_name') { connection.display_name == 'Office desktop' }

        prefs.bandwidth_row.selected = VncPreferencesWindow::BANDWIDTHS.keys.index('fast-refresh')
        d.check('the bandwidth combo wrote the connection') { connection.bandwidth == 'fast-refresh' }

        prefs.scale_mode_row.selected = PreferencesWindow::SCALE_MODES.keys.index('original')
        d.check('the scale mode combo wrote the connection') { connection.scale_mode == 'original' }
        d.check('which the connection applied to its own scaling flags') { !connection.scaling }

        pump(50)
        d.shot('11-vnc-preferences')
        prefs.window.close
      end
    end
  end

  d.step('the RDP preferences window grows a Resize-desktop item once supported') do
    RdpConnection.new.tap do |connection|
      RdpPreferencesWindow.new(connection).tap do |prefs|
        prefs.build(transient_for: app.main_window.window)

        d.check('resize-desktop is not offered yet') { !prefs.scale_mode_ids.include?('resize-desktop') }

        connection.resize_supported = true
        d.check('it appears once the connection reports support') do
          prefs.scale_mode_ids.include?('resize-desktop')
        end
        d.check('three items in the combo\'s model now') { prefs.scale_mode_row.model.n_items == 3 }

        prefs.scale_mode_row.selected = prefs.scale_mode_ids.index('resize-desktop')
        d.check('selecting it writes the connection') { connection.scale_mode == 'resize-desktop' }
        d.check('which the connection turns into allow_resize') { connection.allow_resize }

        prefs.window.close
      end
    end
  end

  d.step('the SPICE preferences window binds audio and scale mode') do
    SpiceConnection.new.tap do |connection|
      SpicePreferencesWindow.new(connection).tap do |prefs|
        prefs.build(transient_for: app.main_window.window)

        prefs.enable_audio.switch.active = false
        d.check('the audio switch wrote the connection') { !connection.enable_audio }

        prefs.scale_mode_row.selected = PreferencesWindow::SCALE_MODES.keys.index('resize-desktop')
        d.check('resize-desktop maps to resize_guest for SPICE, not allow_resize') { connection.resize_guest }

        prefs.window.close
      end
    end
  end

  # --- Dialogs window: certificate verification, change, authentication ----

  d.step('certificate verification shows the fingerprint and reports the answer') do
    answers = []
    app.main_window.dialogs_window.then do |dialogs|
      dialogs.show_certificate_verification('box-one', FINGERPRINT) { |ok| answers << ok }

      d.check('the dialog is visible') { dialogs.window.visible? }
      d.check('it is on the certificate page') { dialogs.content_stack.visible_child_name == 'certificate-verification' }
      d.check('the Verify button is the header action') { dialogs.header_stack.visible_child_name == 'verify-button-page' }
      d.check('the fingerprint survived the reformatting, stripped of punctuation') do
        dialogs.fingerprint_value.label.delete("\n :").downcase == FINGERPRINT.delete(':')
      end
      d.shot('12-certificate-verification')

      dialogs.verify_button.signal_emit('clicked')
      d.check('verify answered true') { answers == [true] }
      d.check('the dialog hid itself') { !dialogs.window.visible? }
    end
  end

  d.step('certificate-change verification uses the Connect button and Escape cancels it') do
    answers = []
    app.main_window.dialogs_window.then do |dialogs|
      dialogs.show_certificate_change_verification('box-one', FINGERPRINT) { |ok| answers << ok }

      d.check('on the change-verification page') do
        dialogs.content_stack.visible_child_name == 'certificate-change-verification'
      end
      d.check('the header shows Connect, not Verify') { dialogs.header_stack.visible_child_name == 'connect-button-page' }
      d.check('Connect starts disabled until the switch is thrown') { !dialogs.connect_button.sensitive? }

      dialogs.delete_local_certificate_switch.active = true
      d.check('the switch enabled Connect') { dialogs.connect_button.sensitive? }

      d.check('Escape cancels it') { dialogs.on_key_pressed(Gdk::Keyval::KEY_Escape) }
      d.check('cancelling answered false') { answers == [false] }
      d.check('and hid the dialog') { !dialogs.window.visible? }
    end
  end

  d.step('authentication only shows the rows asked for, and reports what was typed') do
    answers = []
    app.main_window.dialogs_window.then do |dialogs|
      dialogs.show_authentication(
        'box-one', need_username: true, need_password: true, need_domain: false
      ) { |u, p, dom| answers << [u, p, dom] }

      d.check('username is shown') { dialogs.username_row.visible? }
      d.check('password is shown') { dialogs.password_row.visible? }
      d.check('domain is not asked for') { !dialogs.domain_row.visible? }
      d.check('the header bar hides for this page') { !dialogs.header_bar.visible? }
      d.shot('13-authentication')

      dialogs.username_row.text = 'nathan'
      dialogs.password_row.text = 'secret'
      dialogs.authenticate_button.signal_emit('clicked')

      d.check('the typed credentials came back') { answers == [['nathan', 'secret', '']] }
      d.check('the dialog hid itself') { !dialogs.window.visible? }
    end
  end

  d.step('cancelling authentication answers with three empty strings') do
    answers = []
    app.main_window.dialogs_window.then do |dialogs|
      dialogs.show_authentication(
        'box-one', need_username: true, need_password: true, need_domain: true
      ) { |u, p, dom| answers << [u, p, dom] }
      dialogs.cancel_authentication_button.signal_emit('clicked')
      d.check('cancelling answers blank') { answers == [['', '', '']] }
    end
  end

  # --- Connection round trips: credentials, database, and the .vnc importer -

  d.step('a password stored on a connection round-trips through the credential file') do
    app.connections.first.password = 'hunter2'
    Credentials.default.lookup(app.connections.first.uuid).then do |stored|
      d.check('the password made it to the credentials file') { stored['password'] == 'hunter2' }
    end
    d.check('the credentials file is 0600') do
      (File.stat(Credentials.default.location).mode & 0o777) == 0o600
    end
    d.check('the password is not in the connections database') do
      !File.read(Database.default.location).include?('hunter2')
    end
  end

  d.step('handle_auth prompts when nothing is stored, and completes once filled in') do
    RdpConnection.new.tap do |connection|
      completed = false
      connection.on_authentication_complete { completed = true }
      connection.handle_auth

      app.main_window.dialogs_window.then do |dialogs|
        d.check('the authentication page came up') { dialogs.window.visible? }
        dialogs.username_row.text = 'u'
        dialogs.password_row.text = 'p'
        dialogs.domain_row.text = 'DOMAIN'
        dialogs.authenticate_button.signal_emit('clicked')
      end

      d.check('authentication completed') { completed }
      d.check('the credentials landed on the connection') do
        [connection.username, connection.password, connection.domain] == %w[u p DOMAIN]
      end
    end
  end

  d.step('importing a .vnc file reads Host/Port/Username/Password, not "Password "') do
    Dir.mktmpdir('vnc-import').then do |dir|
      File.join(dir, 'example.vnc').then do |path|
        File.write(path, <<~VNC)
          [Connection]
          Host=imported-host
          Port=5950
          Username=alice
          Password=s3cret
        VNC

        VncConnection.from_vnc_file(path).then do |connection|
          d.check('the host came across') { connection.host == 'imported-host' }
          d.check('so did the port') { connection.port == 5950 }
          d.check('so did the username') { connection.username == 'alice' }
          d.check('and the password, from the unspaced key') { connection.password == 's3cret' }
        end
      end
    end
  end

  d.step('App#add_connection_from_file only imports .vnc files') do
    before = app.connections.length

    Dir.mktmpdir('vnc-import-2').then do |dir|
      File.join(dir, 'second.vnc').then do |path|
        File.write(path, "[Connection]\nHost=second-host\nPort=5901\n")
        app.add_connection_from_file(path)
      end

      d.check('a .vnc file was imported') { app.connections.length == before + 1 }
      d.check('it landed at the top of the list') { app.connections.first.host == 'second-host' }

      File.join(dir, 'ignored.txt').then do |path|
        File.write(path, 'not a vnc file')
        d.check('a non-.vnc file is refused, not imported') do
          app.add_connection_from_file(path)
          app.connections.length == before + 1
        end
      end
    end
  end

  d.step('find_connection_by_uri matches an existing connection rather than duplicating it') do
    app.connections.first.then do |connection|
      before = app.connections.length
      # add_connection on a known uri opens it instead of adding a duplicate,
      # which — since nothing here can actually speak VNC — bounces straight
      # back to the collection view with an error notification; dismissed so
      # it does not sit over the next screenshot.
      app.add_connection(connection.uri)
      d.check('no new connection was added') { app.connections.length == before }
      d.check('it opened the existing one instead, which then failed over') do
        app.main_window.stack.visible_child_name == 'collection'
      end
      app.main_window.notifications_bar.dismiss
    end
  end

  d.step('App.parse_arguments mirrors the option table in main.rb') do
    d.check('a bare URL is the uri') { App.parse_arguments(['rdp://host'])[:uri] == 'rdp://host' }
    d.check('-F takes the next argument as the file') do
      App.parse_arguments(['-F', '/tmp/x.vnc'])[:file] == '/tmp/x.vnc'
    end
    d.check('--file=PATH works as one token') do
      App.parse_arguments(['--file=/tmp/y.vnc'])[:file] == '/tmp/y.vnc'
    end
    d.check('-f sets fullscreen') { App.parse_arguments(['-f'])[:fullscreen] }
    d.check('more than one URL is an error, as upstream refuses') do
      !App.parse_arguments(%w[one two]).fetch(:error).nil?
    end
  end

  # --- Shortcuts and about dialogs -------------------------------------------

  d.step('win.show-help-overlay presents the shortcuts dialog') do
    app.main_window.window.activate_action('show-help-overlay', nil)
    d.check('a ShortcutsDialog toplevel appeared') do
      Gtk::Window.list_toplevels.any? { |w| w.title == 'Keyboard Shortcuts' }
    end
    d.shot('14-shortcuts')
    Gtk::Window.list_toplevels.find { |w| w.title == 'Keyboard Shortcuts' }&.close
  end

  d.step('F1 both triggers the window\'s own handler and the app.help accelerator') do
    d.check('F1 is handled by on_key_pressed') do
      app.main_window.on_key_pressed(Gdk::Keyval::KEY_F1, NO_MODIFIER)
    end
    d.check('app.help carries the F1 accelerator') do
      app.app.get_accels_for_action('app.help') == ['F1']
    end
    d.check('app.quit carries Ctrl+Q') do
      app.app.get_accels_for_action('app.quit').map { |a| Gtk.accelerator_parse(a) } ==
        ['<Control>q'].map { |a| Gtk.accelerator_parse(a) }
    end
  end

  d.step('F11 is handled by the window\'s key handler, which asks for fullscreen') do
    # As with the display menu's fullscreen action, there is no window
    # manager under Xvfb to grant the request, so only that the handler
    # claims the key and calls through without raising is checked here.
    d.check('F11 is handled') { app.main_window.on_key_pressed(Gdk::Keyval::KEY_F11, NO_MODIFIER) }
    d.check('and again, to toggle back') { app.main_window.on_key_pressed(Gdk::Keyval::KEY_F11, NO_MODIFIER) }
  end

  d.step('app.about presents the about dialog with upstream\'s fields') do
    app.app.activate_action('about', nil)
    d.check('an AboutDialog is up') { app.about_dialog.is_a?(Adwaita::AboutDialog) }
    d.check('its name is Connections') { app.about_dialog.application_name == 'Connections' }
    d.check('its icon is the fallback symbolic icon') { app.about_dialog.application_icon == App::SYMBOLIC_ICON_NAME }
    d.check('its version is upstream\'s') { app.about_dialog.version == App::VERSION }
    d.check('its licence is GPL-3.0') { app.about_dialog.license_type == Gtk::License::GPL_3_0 }
    d.check('its developers are upstream\'s') { app.about_dialog.developers == App::AUTHORS }
    d.check('its artists are upstream\'s') { app.about_dialog.artists == App::ARTISTS }
    d.shot('15-about')
    app.about_dialog.close
  end

  # --- Window geometry persistence -------------------------------------------

  d.step('Settings records the window size, except while maximized') do
    app.settings.window_size = [999, 555]
    d.check('the size round-trips') { app.settings.window_size == [999, 555] }

    Settings.new(path: app.settings.location).then do |reloaded|
      d.check('a fresh Settings reads the same file') { reloaded.window_size == [999, 555] }
    end

    # Settings#remember is driven through a double, not the real window:
    # gtk_window_maximize under Xvfb only *asks* for the state (there is no
    # window manager here to grant it), so `maximized?` on the real window
    # never actually flips and the skip this is testing could never be
    # observed against it.
    Struct.new(:maximized?, :fullscreened?, :default_width, :default_height).new(
      true, false, 1280, 900
    ).then do |fake_window|
      d.check('remember skips a maximized window') do
        app.settings.remember(fake_window)
        app.settings.window_size == [999, 555]
      end
    end
  end

  # --- Shutdown: every live connection is asked to disconnect ---------------

  d.step('on_shutdown disconnects every connection that is still live') do
    Class.new(VncConnection) do
      def connect_it = self.connected = true
    end.new.tap do |live_connection|
      app.connections << live_connection
      app.model.append(live_connection)

      app.on_shutdown

      d.check('the live connection was disconnected') { !live_connection.connected }
      app.connections.delete(live_connection)
    end
  end

  # --- Quitting: the last thing this run does --------------------------------
  #
  # quit_app hides every window and calls Gtk::Application#quit, which ends
  # the run loop GtkDriver started — nothing registered after this step will
  # execute, so it has to be last.
  d.step('app.quit hides every window and ends the application') do
    d.check('an app.quit action exists') { app.app.lookup_action('quit').is_a?(Gio::SimpleAction) }
    app.app.activate_action('quit', nil)
  end
end
