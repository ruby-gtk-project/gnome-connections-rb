# frozen_string_literal: true

require 'adwaita'

require_relative 'preferences_widgets'

# SpicePreferencesWindow edits a SPICE connection.
#
# Ported from upstream's src/spice-preferences-window.vala and
# src/ui/spice-preferences.ui: the address and name, the audio switch and the
# scale-mode combo. Like the rest of the SPICE support it is only reachable in
# a build that can speak SPICE.
#
class SpicePreferencesWindow < PreferencesWindow
  def build(transient_for: nil)
    window.tap do |win|
      win.transient_for = transient_for
      win.add(page)

      page.tap do |p|
        p.add(address_group)
        p.add(display_group)
      end

      display_group.tap do |group|
        group.add(enable_audio.build)
        group.add(scale_mode_row)
      end

      bind_widget_property(connection_name_row, 'text', :display_name)
      bind_widget_property(host_address_label, 'label', :uri)
      bind_widget_property(enable_audio.switch, 'active', :enable_audio)
      bind_combo_property(scale_mode_row, SCALE_MODES.keys, :scale_mode)
    end
  end

  def display_group
    @display_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'Display'
    end
  end

  def enable_audio = @enable_audio ||= BooleanProperty.new('Enable audio')

  def scale_mode_row
    @scale_mode_row ||= Adwaita::ComboRow.new.tap do |row|
      row.title = 'Scale mode'
      row.model = Gtk::StringList.new(SCALE_MODES.values)
    end
  end
end
