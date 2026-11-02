# frozen_string_literal: true

require 'adwaita'

require_relative 'preferences_widgets'

# RdpPreferencesWindow edits an RDP connection.
#
# Ported from upstream's src/rdp-preferences-window.vala and
# src/ui/rdp-preferences.ui. The .ui file offers only "Fit window" and
# "Original size"; upstream inserts "Resize desktop" at the top the moment the
# display reports that the server supports resizing, or when the connection is
# already set to it, and keeps watching for that in case it arrives later.
#
class RdpPreferencesWindow < PreferencesWindow
  BASE_SCALE_MODES = {
    'fit-window' => 'Fit window',
    'original'   => 'Original size',
  }.freeze

  RESIZE_DESKTOP = 'resize-desktop'

  # Translators: Combo item for resizing remote desktop to window's size.
  RESIZE_DESKTOP_LABEL = 'Resize desktop'

  def build(transient_for: nil)
    window.tap do |win|
      win.transient_for = transient_for
      win.add(page)

      page.tap do |p|
        p.add(address_group)
        p.add(display_group)
      end

      display_group.add(scale_mode_row)

      update_scale_mode_combo

      bind_widget_property(connection_name_row, 'text', :display_name)
      bind_widget_property(host_address_label, 'label', :uri)
      bind_combo_property(scale_mode_row, -> { scale_mode_ids }, :scale_mode)

      connection.on_property_changed(:resize_supported) { update_scale_mode_combo }
    end
  end

  # Upstream's update_scale_mode_combo plus combo_contains_item.
  def update_scale_mode_combo
    (connection.resize_supported || connection.scale_mode == RESIZE_DESKTOP).then do |resizable|
      if resizable && !scale_mode_ids.include?(RESIZE_DESKTOP)
        @scale_mode_ids = [RESIZE_DESKTOP] + BASE_SCALE_MODES.keys
        scale_mode_row.model = Gtk::StringList.new(
          [RESIZE_DESKTOP_LABEL] + BASE_SCALE_MODES.values,
        )
        select_combo_item(scale_mode_row, scale_mode_ids, :scale_mode)
      end
    end
  end

  def scale_mode_ids = @scale_mode_ids ||= BASE_SCALE_MODES.keys

  def display_group
    @display_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = 'Display'
    end
  end

  def scale_mode_row
    @scale_mode_row ||= Adwaita::ComboRow.new.tap do |row|
      row.title = 'Scale mode'
      row.model = Gtk::StringList.new(BASE_SCALE_MODES.values)
    end
  end
end
