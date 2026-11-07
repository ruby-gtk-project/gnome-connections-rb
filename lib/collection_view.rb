# frozen_string_literal: true

require 'adwaita'

require_relative 'collection_view_child'
require_relative 'actions_popover'

# CollectionView is the page listing the saved connections: a search bar above
# a grid of tiles.
#
# Ported from upstream's src/collection-view.vala and
# src/ui/collection-view.ui. Activating a tile opens its connection,
# right-clicking one opens the actions popover, and typing in the search entry
# filters the grid on the address and the display name.
#
# Upstream fills the grid with Gtk.FlowBox.bind_model. This port fills it from
# the application's own Array of connections instead: a Ruby object read back
# out of a GTK list model can outlive the reference that kept it alive, and
# touching it then crashes rather than raising. The tiles, the filtering and
# the ordering are the same either way.
#
class CollectionView
  # Exposed for the drive harness: the tile widgets, in the same order as the
  # connections they were built from, and the CollectionViewChild wrapper
  # behind each one (which holds the connection itself).
  attr_reader :tiles, :children

  def initialize
    @children = []
    @tiles = []
  end

  def build
    scroller.tap do |sw|
      sw.child = box

      box.tap do |b|
        b.append(search_bar)
        b.append(flowbox)

        search_bar.tap do |bar|
          bar.child = search_entry
          search_entry.signal_connect('search-changed') { on_search_changed }
        end

        flowbox.tap do |fb|
          fb.set_filter_func { |child| model_filter(child) }
          fb.signal_connect('child-activated') { |_fb, child| on_child_activated(child) }
          fb.add_controller(context_menu_gesture)
        end

        context_menu_gesture.signal_connect('released') do |_gesture, _n, x, y|
          launch_context_popover_at(x, y)
        end
      end
    end
  end

  # Upstream's bind_model. Rebuilding the tiles is what an items-changed on the
  # application's model arrives as here.
  def refresh(connections)
    @children.each(&:cancel_refresh)
    @tiles.each { |tile| flowbox.remove(tile) }
    @children = []
    @tiles = []

    connections.each do |connection|
      CollectionViewChild.new(connection).tap do |child|
        @children << child
        flowbox_child(child).tap do |tile|
          @tiles << tile
          flowbox.insert(tile, -1)
        end
      end
    end

    flowbox.invalidate_filter
  end

  def search_bar
    @search_bar ||= Gtk::SearchBar.new.tap do |bar|
      bar.show_close_button = false
    end
  end

  def search_entry
    @search_entry ||= Gtk::SearchEntry.new.tap do |entry|
      entry.width_chars = 40
      entry.hexpand = true
    end
  end

  def scroller
    @scroller ||= Gtk::ScrolledWindow.new.tap do |sw|
      sw.set_policy(:never, :automatic)
      sw.vexpand = true
    end
  end

  def box
    @box ||= Gtk::Box.new(:vertical, 0).tap do |b|
      b.add_css_class('view')
    end
  end

  def flowbox
    @flowbox ||= Gtk::FlowBox.new.tap do |fb|
      fb.homogeneous = true
      fb.margin_top = 12
      fb.margin_bottom = 12
      fb.margin_start = 12
      fb.margin_end = 12
      fb.row_spacing = 6
      fb.column_spacing = 20
      fb.valign = :start
      fb.selection_mode = :none
    end
  end

  def context_menu_gesture
    @context_menu_gesture ||= Gtk::GestureClick.new.tap do |gesture|
      gesture.button = 3
    end
  end

  def actions_popover
    @actions_popover ||= ActionsPopover.new.tap do |popover|
      popover.build
      popover.popover.set_parent(flowbox)
    end
  end

  private

    def flowbox_child(child)
      Gtk::FlowBoxChild.new.tap do |fbc|
        fbc.halign = :start
        fbc.child = child.build
      end
    end

    # Upstream's on_child_activated.
    def on_child_activated(flowbox_child)
      connection_at(flowbox_child.index).then do |connection|
        if connection
          App.instance.open_connection(connection)
        end
      end
    end

    # Upstream's on_button_release_event plus launch_context_popover_for_child:
    # the tile under the pointer is the one the popover acts on.
    def launch_context_popover_at(x, y)
      flowbox.get_child_at_pos(x, y).then do |flowbox_child|
        if flowbox_child
          connection_at(flowbox_child.index).then do |connection|
            if connection
              actions_popover.update_for_item(connection)
              actions_popover.popover.pointing_to = Gdk::Rectangle.new(
                x.to_i,
                y.to_i,
                1,
                1,
              )
              actions_popover.popover.popup
            end
          end
        end
      end
    end

    # Upstream's model_filter: the address or the display name has to contain
    # whatever is in the search entry.
    def model_filter(flowbox_child)
      connection_at(flowbox_child.index).then do |connection|
        if connection
          connection.uri.include?(search_entry.text) ||
            connection.display_name.to_s.include?(search_entry.text)
        else
          false
        end
      end
    end

    def on_search_changed = flowbox.invalidate_filter

    def connection_at(index)
      @children[index]&.connection
    end
end
