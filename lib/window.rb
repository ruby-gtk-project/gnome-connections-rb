# frozen_string_literal: true

require 'adwaita'

require_relative 'topbar'
require_relative 'collection_view'
require_relative 'display_view'
require_relative 'notifications'
require_relative 'dialogs_window'
require_relative 'shortcuts_dialog'
require_relative 'vnc_connection'
require_relative 'rdp_connection'
require_relative 'spice_connection'
require_relative 'vnc_preferences_window'
require_relative 'rdp_preferences_window'
require_relative 'spice_preferences_window'

# Window is the application window.
#
# Ported from upstream's src/window.vala and src/ui/window.ui: a stack holding
# the collection view, the empty state, the display view and a loading
# spinner, with the notifications bar overlaid on top and the topbar as the
# title bar. It restores and records its size, keeps the search button and the
# search bar in step, and binds the five keyboard shortcuts upstream's
# on_key_pressed handles.
#
class Window
  # Upstream debounces the geometry save by 100ms so dragging a window edge
  # does not write the file on every step.
  SAVE_GEOMETRY_TIMEOUT = 100

  attr_reader :collection_view, :notifications_bar, :dialogs_window, :topbar, :display_view

  def initialize(app, application: nil, settings: nil, present: true)
    @app = app
    @application = application
    @settings = settings
    @present = present
    @configure_id = 0
    @topbar = Topbar.new
    @collection_view = CollectionView.new
    @display_view = DisplayView.new
    @notifications_bar = NotificationsBar.new
    @dialogs_window = DialogsWindow.new
  end

  def build
    window.tap do |win|
      win.add_action(show_help_overlay_action)
      win.child = toolbar_view

      # Upstream packs the topbar as the window's titlebar; under Libadwaita
      # the header bars belong to a toolbar view instead, which is what gives
      # them their flat, undecorated look.
      toolbar_view.tap do |view|
        view.add_top_bar(topbar.build)
        view.content = overlay
      end

      overlay.tap do |ov|
        ov.child = stack
        ov.add_overlay(notifications_bar.build)

        stack.tap do |s|
          s.add_named(collection_view.build, 'collection')
          s.add_named(empty_view, 'empty')
          s.add_named(display_view.build, 'display')
          s.add_named(loading_view, 'loading')

          loading_view.append(loading_spinner)

          s.visible_child_name = 'empty'
        end
      end

      key_controller.signal_connect('key-pressed') do |_controller, keyval, _code, state|
        on_key_pressed(keyval, state)
      end
      win.add_controller(key_controller)

      # Upstream binds the search button's "active" to the search bar's
      # "search-mode-enabled" bidirectionally.
      topbar.search_button.signal_connect('toggled') do |button|
        collection_view.search_bar.search_mode_enabled = button.active?
      end
      collection_view.search_bar.signal_connect('notify::search-mode-enabled') do |bar, _p|
        topbar.search_button.active = bar.search_mode_enabled?
      end

      win.signal_connect('close-request') do
        notifications_bar.dismiss
        false
      end

      %w[notify::default-width notify::default-height].each do |signal|
        win.signal_connect(signal) { on_configure }
      end

      dialogs_window.build(transient_for: win)
      @settings&.apply_to(win)

      if @application.to_s.end_with?('.Devel')
        win.add_css_class('devel')
      end

      if @present
        win.present
      end
    end
  end

  # Upstream's items_changed: the empty state stands in for the grid until
  # there is something in it.
  def items_changed(connections)
    collection_view.refresh(connections)
    topbar.search_button.visible = !connections.empty?

    if connections.empty?
      stack.visible_child_name = 'empty'
    else
      stack.visible_child_name = 'collection'
    end
  end

  # Upstream's open_connection: show the display view, retitle the topbar, and
  # either connect or switch to an already-connected display.
  def open_connection(connection)
    stack.visible_child_name = 'display'
    topbar.show_display_view(connection)

    if connection.connected
      display_view.switch_to(connection)
    else
      display_view.connect_to(connection)
    end
  end

  # Upstream's show_collection_view.
  def show_collection_view
    stack.visible_child_name = 'collection'
    topbar.show_collection_view
    topbar.title = 'Connections'
  end

  # Upstream's show_preferences_window.
  def show_preferences_window(connection)
    preferences_window_class(connection).then do |klass|
      if klass
        klass.new(connection).tap do |preferences|
          preferences.build(transient_for: window)
          preferences.present
        end
      else
        warn "Failed to launch preferences window for #{connection.uri}"
      end
    end
  end

  def present = window.present

  def fullscreened? = window.fullscreened?

  def fullscreened=(value)
    if value
      window.fullscreen
    else
      window.unfullscreen
    end
  end

  def window
    @window ||= Gtk::ApplicationWindow.new(@app).tap do |win|
      win.title = 'Connections'
      win.resizable = true
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def overlay = @overlay ||= Gtk::Overlay.new

  def stack
    @stack ||= Gtk::Stack.new.tap do |s|
      s.vexpand = true
      s.hexpand = true
    end
  end

  def empty_view
    @empty_view ||= Adwaita::StatusPage.new.tap do |page|
      page.icon_name = App::SYMBOLIC_ICON_NAME
      page.title = 'Welcome to Connections'
      page.description = 'Click the add button to create your first connection'
    end
  end

  def loading_view
    @loading_view ||= Gtk::Box.new(:horizontal, 0).tap do |b|
      b.halign = :center
      b.valign = :center
      b.vexpand = true
    end
  end

  def loading_spinner
    @loading_spinner ||= Gtk::Spinner.new.tap do |spinner|
      spinner.spinning = true
      spinner.set_size_request(32, 32)
    end
  end

  def key_controller = @key_controller ||= Gtk::EventControllerKey.new

  # Upstream's menu item for the shortcuts window acts through
  # win.show-help-overlay, which is the action GtkApplicationWindow provides
  # for a GtkShortcutsWindow; this port's shortcuts list is an
  # Adwaita::ShortcutsDialog, so the action presents that instead.
  def show_help_overlay_action
    @show_help_overlay_action ||= Gio::SimpleAction.new('show-help-overlay').tap do |action|
      action.enabled = true
      action.signal_connect('activate') { show_shortcuts }
    end
  end

  def show_shortcuts
    ShortcutsDialog.new.tap do |dialog|
      dialog.build
      dialog.present(window)
    end
  end

  # Upstream's on_key_pressed. The last clause hands anything else to the
  # search bar while the collection view is up, which is what starts a search
  # as soon as the user types.
  def on_key_pressed(keyval, state)
    control = state.control_mask?

    if keyval == Gdk::Keyval::KEY_f && control
      collection_view.search_bar.search_mode_enabled =
        !collection_view.search_bar.search_mode_enabled?
      true
    elsif keyval == Gdk::Keyval::KEY_F11
      self.fullscreened = !fullscreened?
      true
    elsif keyval == Gdk::Keyval::KEY_q && control
      App.instance.quit_app
      true
    elsif keyval == Gdk::Keyval::KEY_F1
      @app.activate_action('help', nil)
      true
    elsif keyval == Gdk::Keyval::KEY_n && control
      topbar.assistant.popup
      true
    else
      false
    end
  end

  private

    def preferences_window_class(connection)
      {
        VncConnection   => VncPreferencesWindow,
        RdpConnection   => RdpPreferencesWindow,
        SpiceConnection => SpicePreferencesWindow,
      }[connection.class]
    end

    # Upstream's on_configure_event plus save_window_geometry: the size is
    # recorded once the resizing has settled, and never while fullscreen.
    def on_configure
      fullscreened?.then do |fullscreen|
        unless fullscreen
          @configure_id.positive?.then do |pending|
            if pending
              GLib::Source.remove(@configure_id)
            end
          end

          @configure_id = GLib::Timeout.add(SAVE_GEOMETRY_TIMEOUT) do
            @configure_id = 0
            @settings&.remember(window)
            display_view.report_size(window.default_width, window.default_height)
            GLib::Source::REMOVE
          end
        end
      end
    end
end
