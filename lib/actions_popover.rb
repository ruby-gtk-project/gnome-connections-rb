# frozen_string_literal: true

require 'adwaita'

# ActionsPopover is the context menu a connection's tile offers on
# right-click: Delete and Properties.
#
# A direct port of upstream's src/actions-popover.vala, including the
# "connection" action group the two menu items act through.
#
class ActionsPopover
  def initialize
    @connection = nil
  end

  def build
    popover.tap do |p|
      p.insert_action_group('connection', action_group)
      p.menu_model = menu
    end
  end

  # Upstream's update_for_item: the popover acts on whichever connection it was
  # last opened for.
  def update_for_item(connection)
    @connection = connection
    %w[delete properties].each do |name|
      action_group.lookup_action(name).enabled = true
    end
    popover.menu_model = menu
  end

  def popover = @popover ||= Gtk::PopoverMenu.new(menu)

  def menu
    @menu ||= Gio::Menu.new.tap do |model|
      model.append('Delete', 'connection.delete')
      model.append('Properties', 'connection.properties')
    end
  end

  def action_group
    @action_group ||= Gio::SimpleActionGroup.new.tap do |group|
      group.add_action(delete_action)
      group.add_action(properties_action)
    end
  end

  def delete_action
    @delete_action ||= Gio::SimpleAction.new('delete').tap do |action|
      action.signal_connect('activate') { delete_activated }
    end
  end

  def properties_action
    @properties_action ||= Gio::SimpleAction.new('properties').tap do |action|
      action.signal_connect('activate') { properties_activated }
    end
  end

  private

    def delete_activated
      @connection.then do |connection|
        if connection
          App.instance.remove_connection(connection)
        end
      end
    end

    def properties_activated
      @connection.then do |connection|
        if connection
          App.instance.main_window.show_preferences_window(connection)
        end
      end
    end
end
