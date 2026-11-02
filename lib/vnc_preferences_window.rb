# frozen_string_literal: true

require 'adwaita'

require_relative 'preferences_widgets'

# VncPreferencesWindow edits a VNC connection.
#
# Ported from upstream's src/vnc-preferences-window.vala and
# src/ui/vnc-preferences.ui: the address and name, the view-only, local-pointer
# and audio switches, and the bandwidth and scale-mode combos.
#
class VncPreferencesWindow < PreferencesWindow
  BANDWIDTHS = {
    'high-quality' => 'High quality',
    'fast-refresh' => 'Fast refresh',
  }.freeze

  def build(transient_for: nil)
    window.tap do |win|
      win.transient_for = transient_for
      win.add(page)

      page.tap do |p|
        p.add(address_group)
        p.add(display_group)
      end

      display_group.tap do |group|
        group.add(view_only.build)
        group.add(show_local_pointer.build)
        group.add(enable_audio.build)
        group.add(bandwidth_row)
        group.add(scale_mode_row)
      end

      bind_widget_property(connection_name_row, 'text', :display_name)
      bind_widget_property(host_address_label, 'label', :uri)
      bind_widget_property(view_only.switch, 'active', :view_only)
      bind_widget_property(show_local_pointer.switch, 'active', :show_local_pointer)
      bind_widget_property(enable_audio.switch, 'active', :enable_audio)
      bind_combo_property(bandwidth_row, BANDWIDTHS.keys, :bandwidth)
      bind_combo_property(scale_mode_row, SCALE_MODES.keys, :scale_mode)
    end
  end

  def display_group
    @display_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'Display'
    end
  end

  def view_only = @view_only ||= BooleanProperty.new('View only')
  def show_local_pointer = @show_local_pointer ||= BooleanProperty.new('Show local pointer')
  def enable_audio = @enable_audio ||= BooleanProperty.new('Enable audio')

  def bandwidth_row
    @bandwidth_row ||= Adwaita::ComboRow.new.tap do |row|
      row.title = 'Bandwidth'
      row.model = Gtk::StringList.new(BANDWIDTHS.values)
    end
  end

  def scale_mode_row
    @scale_mode_row ||= Adwaita::ComboRow.new.tap do |row|
      row.title = 'Scale mode'
      row.model = Gtk::StringList.new(SCALE_MODES.values)
    end
  end
end
