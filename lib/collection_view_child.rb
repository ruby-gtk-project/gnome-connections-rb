# frozen_string_literal: true

require 'adwaita'

# CollectionViewChild is one tile in the collection grid: a thumbnail of the
# remote display with the connection's name underneath.
#
# Ported from upstream's src/collection-view-child.vala and
# src/ui/collection-view-child.ui. The tile starts out showing the application
# icon, and once the connection reports that its display has something to
# draw, a three-second timeout keeps the thumbnail up to date for as long as
# the connection stays up.
#
class CollectionViewChild
  THUMBNAIL_WIDTH = 180
  THUMBNAIL_HEIGHT = 134
  REFRESH_INTERVAL = 3

  attr_reader :connection

  def initialize(connection)
    @connection = connection
    @thumbnail_id = 0
  end

  def build
    box.tap do |b|
      b.append(thumbnail)
      b.append(connection_name)

      update_display_name
      @connection.on_property_changed(:display_name) { update_display_name }
      @connection.on_show { update_thumbnail }
    end
  end

  def update_display_name
    connection_name.text = @connection.visible_name
  end

  # Upstream's update_thumbnail: refresh the tile every three seconds while the
  # connection is up, and fall back to the icon once it is not.
  def update_thumbnail
    cancel_refresh

    @thumbnail_id = GLib::Timeout.add_seconds(REFRESH_INTERVAL) do
      if @connection.connected
        refresh_thumbnail
      else
        @thumbnail_id = 0
        thumbnail.set_from_icon_name(default_thumbnail_icon)
        GLib::Source::REMOVE
      end
    end
  end

  # Detaches the refresh timeout. Upstream does this in the tile's destructor;
  # here the collection view calls it when it drops the tile.
  def cancel_refresh
    @thumbnail_id.positive?.then do |pending|
      if pending
        GLib::Source.remove(@thumbnail_id)
        @thumbnail_id = 0
      end
    end
  end

  def box
    @box ||= Gtk::Box.new(:vertical, 0).tap do |b|
      b.halign = :start
    end
  end

  def thumbnail
    @thumbnail ||= Gtk::Image.new.tap do |image|
      image.pixel_size = 24
      image.halign = :fill
      image.margin_top = 10
      image.margin_bottom = 10
      image.margin_start = 10
      image.margin_end = 10
      image.set_size_request(THUMBNAIL_WIDTH, THUMBNAIL_HEIGHT)
      image.add_css_class('thumbnail')
      image.set_from_icon_name(default_thumbnail_icon)
    end
  end

  def connection_name
    @connection_name ||= Gtk::Label.new.tap do |label|
      label.set_size_request(192, -1)
      label.max_width_chars = 20
      label.justify = :center
      label.halign = :start
      label.hexpand = true
      label.valign = :center
      label.ellipsize = :middle
      label.lines = 3
      label.wrap = true
      label.wrap_mode = :word_char
      label.margin_top = 10
    end
  end

  private

    # Upstream uses its own "<application-id>-symbolic" icon, which ships in its
    # gresource bundle; this port ships no icon theme of its own, so the tile
    # falls back to the stock icon the application window uses.
    def default_thumbnail_icon = App::SYMBOLIC_ICON_NAME

    def refresh_thumbnail
      @connection.thumbnail.then do |pixbuf|
        if pixbuf
          thumbnail.set_from_paintable(
            Gdk::Texture.new(
              pixbuf.scale_simple(THUMBNAIL_WIDTH, THUMBNAIL_HEIGHT, :bilinear),
            ),
          )
          GLib::Source::CONTINUE
        else
          @thumbnail_id = 0
          GLib::Source::REMOVE
        end
      end
    end
end
