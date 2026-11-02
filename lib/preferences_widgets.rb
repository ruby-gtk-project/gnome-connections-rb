# frozen_string_literal: true

require 'adwaita'

# PreferencesWindow is the base class the three protocol preferences windows
# share, and BooleanProperty is the switch row they build their on/off
# settings from.
#
# Ported from upstream's src/preferences-widgets.vala. Upstream's
# bind_widget_property leans on GObject's bind_property to keep a widget and a
# connection property in step; the connection properties here are plain Ruby
# accessors, so the same two-way binding is wired by hand: the widget's value
# is set from the connection now, a change to the widget writes the connection,
# and a change to the connection writes the widget.
#
class PreferencesWindow
  # The three scale modes upstream's combos offer, in its order.
  SCALE_MODES = {
    'resize-desktop' => 'Resize desktop',
    'fit-window'     => 'Fit window',
    'original'       => 'Original size',
  }.freeze

  attr_reader :connection

  def initialize(connection)
    @connection = connection
    @binding_in_progress = false
  end

  def present = window.present

  def window
    @window ||= Adwaita::PreferencesWindow.new.tap do |win|
      win.title = 'Connection preferences'
      win.set_default_size(560, 480)
    end
  end

  def page = @page ||= Adwaita::PreferencesPage.new

  def address_group
    @address_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.add(host_address_row)
      group.add(connection_name_row)
    end
  end

  def host_address_row
    @host_address_row ||= Adwaita::ActionRow.new.tap do |row|
      row.title = 'Address'
      row.add_suffix(host_address_label)
    end
  end

  def host_address_label
    @host_address_label ||= Gtk::Label.new.tap do |label|
      label.valign = :center
      label.selectable = true
      label.add_css_class('dim-label')
    end
  end

  def connection_name_row
    @connection_name_row ||= Adwaita::EntryRow.new.tap do |row|
      row.title = 'Name'
    end
  end

  # Upstream's bind_widget_property. The widget's property is read back with
  # `get_property`, so this works for any widget property the bindings expose.
  def bind_widget_property(widget, widget_property, connection_property)
    widget.set_property(widget_property, @connection.public_send(connection_property))

    widget.signal_connect("notify::#{widget_property.to_s.tr('_', '-')}") do
      guarded do
        @connection.public_send(
          :"#{connection_property}=",
          widget.get_property(widget_property),
        )
      end
    end

    @connection.on_property_changed(connection_property) do
      guarded do
        widget.set_property(widget_property, @connection.public_send(connection_property))
      end
    end
  end

  # The combos upstream binds through "active-id" have no id in Libadwaita: a
  # combo row selects by position. This binds the position to the id the
  # connection stores. `ids` may be an Array, or anything callable returning
  # one, for a combo whose items can grow after it is bound.
  def bind_combo_property(row, ids, connection_property)
    select_combo_item(row, ids, connection_property)

    row.signal_connect('notify::selected') do
      guarded do
        ids_for(ids)[row.selected].then do |id|
          if id
            @connection.public_send(:"#{connection_property}=", id)
          end
        end
      end
    end

    @connection.on_property_changed(connection_property) do
      guarded { select_combo_item(row, ids, connection_property) }
    end
  end

  # Moves the combo to whichever item holds the connection's current value.
  def select_combo_item(row, ids, connection_property)
    ids_for(ids).index(@connection.public_send(connection_property)).then do |index|
      if index
        row.selected = index
      end
    end
  end

  private

    def ids_for(ids)
      if ids.respond_to?(:call)
        ids.call
      else
        ids
      end
    end

    # A two-way binding would otherwise bounce: the widget's change writes the
    # connection, whose notification writes the widget, and so on.
    def guarded
      @binding_in_progress.then do |bouncing|
        unless bouncing
          @binding_in_progress = true
          yield
          @binding_in_progress = false
        end
      end
    end
end

# BooleanProperty is an action row carrying a switch, which is what upstream's
# ConnectionsBooleanProperty is.
class BooleanProperty
  def initialize(title)
    @title = title
  end

  def build
    row.tap do |r|
      r.add_suffix(switch)
      r.activatable_widget = switch
    end
  end

  def row
    @row ||= Adwaita::ActionRow.new.tap do |r|
      r.title = @title
    end
  end

  def switch
    @switch ||= Gtk::Switch.new.tap do |s|
      s.valign = :center
    end
  end
end
