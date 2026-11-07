# frozen_string_literal: true

require 'adwaita'

require_relative 'assistant'

# Topbar is the window's title bar: a stack holding the collection header bar
# and the display header bar, and swapping between them as the window moves
# between the two views.
#
# Ported from upstream's src/topbar.vala and src/ui/topbar.ui, including the
# "display" and "key" action groups, the main menu, the display menu and the
# key-input popover that sends Ctrl+Alt combinations to the remote machine.
#
class Topbar
  # Upstream's key_input_action_entries, with the keyvals each one sends.
  #
  # Deliberate deviation from upstream: `topbar.vala`'s
  # `ctrl_alt_fn_activated` allocates `uint[] keyvals = { Control_L, Alt_L, 0 }`
  # (valid indices 0..2) and its `f3` branch assigns `keyvals[3] = Gdk.Key.F3`,
  # one past the end, so upstream's Ctrl+Alt+F3 never actually sends F3
  # (`keyvals[2]` stays 0). This port fixes that bug rather than reproducing
  # it: `ctrl+alt+f3` below sends `F3` for real.
  KEY_COMBINATIONS = {
    'ctrl+alt+backspace' => %w[Control_L Alt_L BackSpace],
    'ctrl+alt+del'       => %w[Control_L Alt_L Delete],
    'ctrl+alt+f1'        => %w[Control_L Alt_L F1],
    'ctrl+alt+f2'        => %w[Control_L Alt_L F2],
    'ctrl+alt+f3'        => %w[Control_L Alt_L F3],
    'ctrl+alt+f7'        => %w[Control_L Alt_L F7],
  }.freeze

  KEY_LABELS = {
    'ctrl+alt+backspace' => 'Ctrl + Alt + Backspace',
    'ctrl+alt+del'       => 'Ctrl + Alt + Del',
    'ctrl+alt+f1'        => 'Ctrl + Alt + F1',
    'ctrl+alt+f2'        => 'Ctrl + Alt + F2',
    'ctrl+alt+f3'        => 'Ctrl + Alt + F3',
    'ctrl+alt+f7'        => 'Ctrl + Alt + F7',
  }.freeze

  attr_reader :assistant

  def initialize
    @connection = nil
    @assistant = Assistant.new
  end

  def build
    stack.tap do |s|
      s.insert_action_group('display', display_action_group)
      s.insert_action_group('key', key_action_group)

      s.add_named(collection_toolbar, 'collection')
      s.add_named(display_toolbar, 'display')

      collection_toolbar.tap do |bar|
        bar.pack_start(new_button)
        bar.pack_end(main_menu_button)
        bar.pack_end(search_button)

        new_button.popover = assistant.build
      end

      display_toolbar.tap do |bar|
        bar.pack_start(back_button)
        bar.pack_end(display_menu_button)
        bar.pack_end(disconnect_button)
        bar.pack_end(keys_menu_button)
        bar.pack_end(fullscreen_button)

        back_button.signal_connect('clicked') { back_button_clicked }
        disconnect_button.signal_connect('clicked') { disconnect_button_clicked }
      end
    end
  end

  # Upstream's show_collection_view.
  def show_collection_view
    @connection = nil
    stack.visible_child_name = 'collection'
  end

  # Upstream's show_display_view.
  def show_display_view(connection)
    @connection = connection
    stack.visible_child_name = 'display'
    display_title.title = connection.visible_name
  end

  # Upstream's set_title, which only ever retitles the collection header bar.
  def title=(title)
    collection_title.title = title
  end

  def search_button
    @search_button ||= Gtk::ToggleButton.new.tap do |button|
      button.icon_name = 'edit-find-symbolic'
      button.valign = :center
      button.visible = false
      button.tooltip_text = 'Search'
      button.add_css_class('image-button')
    end
  end

  def stack = @stack ||= Gtk::Stack.new

  def collection_toolbar
    @collection_toolbar ||= Adwaita::HeaderBar.new.tap do |bar|
      bar.title_widget = collection_title
      bar.show_end_title_buttons = true
      bar.add_css_class('titlebar')
    end
  end

  def collection_title = @collection_title ||= Adwaita::WindowTitle.new('Connections', '')

  def display_toolbar
    @display_toolbar ||= Adwaita::HeaderBar.new.tap do |bar|
      bar.title_widget = display_title
      bar.show_end_title_buttons = true
      bar.add_css_class('titlebar')
    end
  end

  def display_title = @display_title ||= Adwaita::WindowTitle.new('', '')

  def new_button
    @new_button ||= Gtk::MenuButton.new.tap do |button|
      button.icon_name = 'list-add-symbolic'
      button.tooltip_text = 'New'
    end
  end

  def main_menu_button
    @main_menu_button ||= Gtk::MenuButton.new.tap do |button|
      button.icon_name = 'open-menu-symbolic'
      button.tooltip_text = 'Application Menu'
      button.menu_model = main_menu_model
    end
  end

  def main_menu_model
    @main_menu_model ||= Gio::Menu.new.tap do |menu|
      menu.append('Keyboard Shortcuts', 'win.show-help-overlay')
      menu.append('Help', 'app.help')
      menu.append('About Connections', 'app.about')
    end
  end

  def back_button
    @back_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'go-previous-symbolic'
      button.tooltip_text = 'Go Back'
    end
  end

  def display_menu_button
    @display_menu_button ||= Gtk::MenuButton.new.tap do |button|
      button.icon_name = 'view-more-symbolic'
      button.tooltip_text = 'Display Menu'
      button.menu_model = display_menu_model
    end
  end

  def display_menu_model
    @display_menu_model ||= Gio::Menu.new.tap do |menu|
      menu.append('Take Screenshot', 'display.take_screenshot')
      menu.append('Properties', 'display.properties')
    end
  end

  def disconnect_button
    @disconnect_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'system-shutdown-symbolic'
      button.tooltip_text = 'Disconnect'
    end
  end

  def keys_menu_button
    @keys_menu_button ||= Gtk::MenuButton.new.tap do |button|
      button.icon_name = 'input-keyboard-symbolic'
      button.tooltip_text = 'Keyboard Shortcuts'
      button.popover = keys_input_popover
    end
  end

  def keys_input_popover = @keys_input_popover ||= Gtk::PopoverMenu.new(keys_input_menu)

  def keys_input_menu
    @keys_input_menu ||= Gio::Menu.new.tap do |menu|
      KEY_LABELS.each { |name, label| menu.append(label, "key.#{name}") }
    end
  end

  def fullscreen_button
    @fullscreen_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'view-fullscreen-symbolic'
      button.focus_on_click = false
      button.valign = :center
      button.action_name = 'display.fullscreen'
      button.tooltip_text = 'Fullscreen'
    end
  end

  # Upstream's "display" action group: the three items of the display menu.
  def display_action_group
    @display_action_group ||= Gio::SimpleActionGroup.new.tap do |group|
      {
        'take_screenshot' => -> { take_screenshot_activated },
        'fullscreen'      => -> { fullscreen_activated },
        'properties'      => -> { properties_activated },
      }.each do |name, handler|
        group.add_action(
          Gio::SimpleAction.new(name).tap do |action|
            action.enabled = true
            action.signal_connect('activate') { handler.call }
          end,
        )
      end
    end
  end

  # Upstream's "key" action group: one action per key combination.
  def key_action_group
    @key_action_group ||= Gio::SimpleActionGroup.new.tap do |group|
      KEY_COMBINATIONS.each_key do |name|
        group.add_action(
          Gio::SimpleAction.new(name).tap do |action|
            action.enabled = true
            action.signal_connect('activate') { send_combination(name) }
          end,
        )
      end
    end
  end

  # Upstream's back_button_clicked.
  def back_button_clicked
    App.instance.main_window.show_collection_view
    stack.visible_child_name = 'collection'
  end

  # Upstream's disconnect_button_clicked.
  def disconnect_button_clicked
    @connection&.disconnect_it
    back_button_clicked
  end

  private

    def properties_activated
      @connection.then do |connection|
        if connection
          App.instance.main_window.show_preferences_window(connection)
        end
      end
    end

    def take_screenshot_activated
      @connection&.take_screenshot
    end

    def fullscreen_activated
      App.instance.main_window.then do |window|
        window.fullscreened = !window.fullscreened?
      end
    end

    # Upstream's ctrl_alt_* handlers, which all build a keyval array and hand it
    # to the connection.
    def send_combination(name)
      @connection.then do |connection|
        if connection
          connection.send_keys(
            KEY_COMBINATIONS.fetch(name).map { |key| Gdk::Keyval.from_name(key) },
          )
        end
      end
    end
end
