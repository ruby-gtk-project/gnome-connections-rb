# frozen_string_literal: true

require 'adwaita'

# DisplayView is the page that hosts a connection's remote display.
#
# Ported from upstream's src/display-view.vala and src/ui/display-view.ui: a
# stack showing a spinner while the connection is being made and the display
# once it reports that it has something to draw, with the display's size
# flashed up in a label for three seconds whenever it changes and a button to
# leave fullscreen that appears when the pointer reaches the top of the
# screen.
#
# Upstream hosts the display in a Gtk.EventBox and forwards raw scroll and
# motion events into it, because in GTK3 a packed display widget would not see
# them otherwise. GTK4 has no EventBox and delivers input through event
# controllers to the widget under the pointer, so the display sits in a bin and
# receives its own input; the only controller left here is the motion
# controller upstream used for the escape-fullscreen button.
#
# Upstream also drives the size label from Gtk.Widget's size-allocate signal,
# which GTK4 removed; `report_size` is called from the window instead.
#
class DisplayView
  SIZE_LABEL_TIMEOUT = 3

  def initialize
    @connection = nil
    @show_handler = nil
    @size_label_timeout_id = 0
    @width = -1
    @height = -1
  end

  def build
    box.tap do |b|
      b.append(stack)

      stack.tap do |s|
        s.add_named(loading_box, 'loading')
        s.add_named(overlay, 'display')

        loading_box.append(spinner)

        overlay.tap do |ov|
          ov.child = scroller
          ov.add_overlay(size_label)
          ov.add_overlay(escape_fullscreen_button)

          scroller.child = display_bin

          escape_fullscreen_button.signal_connect('clicked') do
            on_escape_fullscreen_button_clicked
          end
        end
      end

      motion_controller.signal_connect('motion') { |_controller, _x, y| on_motion(y) }
      b.add_controller(motion_controller)
    end
  end

  # Upstream's connect_to: show the spinner, host the display, then connect.
  def connect_to(connection)
    stack.visible_child_name = 'loading'
    switch_to(connection)
    connection.connect_it
  end

  # Upstream's switch_to: host this connection's display and wait for it to
  # report that it has something to draw.
  def switch_to(connection)
    replace_display(connection)
    connection.on_show { show_display }
  end

  # Upstream's replace_display.
  def replace_display(connection)
    (display_bin.child == connection.widget).then do |already_hosted|
      unless already_hosted
        remove_display
        @connection = connection
        display_bin.child = connection.widget
      end
    end
  end

  # Upstream's remove_display: drop the display and let the connection dispose
  # of it.
  def remove_display
    display_bin.child = nil

    @connection.then do |connection|
      if connection
        connection.dispose_display
        @connection = nil
      end
    end
  end

  def show_display
    stack.visible_child_name = 'display'
  end

  # Upstream's on_size_allocate: show the new size, then hide the label again
  # three seconds later.
  #
  # Translators: Showing size of widget as WIDTH×HEIGHT here.
  def report_size(width, height)
    (@width == width && @height == height).then do |unchanged|
      unless unchanged
        @width = width
        @height = height
        size_label.label = "#{width}×#{height}"
        size_label.visible = true
        restart_size_label_timeout
      end
    end
  end

  # Upstream's motion_notify_event: in fullscreen, the escape button follows
  # the pointer to the top of the screen.
  def on_motion(y)
    App.instance.main_window.fullscreened?.then do |fullscreen|
      if fullscreen
        escape_fullscreen_button.visible = y < 40
      else
        escape_fullscreen_button.visible = false
      end
    end
  end

  def on_escape_fullscreen_button_clicked
    App.instance.main_window.fullscreened = false
    escape_fullscreen_button.visible = false
  end

  def box
    @box ||= Gtk::Box.new(:vertical, 0).tap do |b|
      b.vexpand = true
    end
  end

  def stack
    @stack ||= Gtk::Stack.new.tap do |s|
      s.vexpand = true
      s.hexpand = true
    end
  end

  def loading_box
    @loading_box ||= Gtk::Box.new(:horizontal, 0).tap do |b|
      b.halign = :center
      b.valign = :center
      b.vexpand = true
    end
  end

  def spinner
    @spinner ||= Gtk::Spinner.new.tap do |s|
      s.spinning = true
      s.set_size_request(32, 32)
    end
  end

  def overlay = @overlay ||= Gtk::Overlay.new

  def scroller
    @scroller ||= Gtk::ScrolledWindow.new.tap do |sw|
      sw.min_content_width = 360
      sw.min_content_height = 294
      sw.vexpand = true
      sw.hexpand = true
    end
  end

  def display_bin = @display_bin ||= Adwaita::Bin.new

  def size_label
    @size_label ||= Gtk::Label.new.tap do |label|
      label.halign = :center
      label.valign = :center
      label.visible = false
      label.add_css_class('app-notification')
    end
  end

  def escape_fullscreen_button
    @escape_fullscreen_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'view-fullscreen-symbolic'
      button.halign = :center
      button.valign = :start
      button.focus_on_click = false
      button.visible = false
      button.add_css_class('app-notification')
    end
  end

  def motion_controller = @motion_controller ||= Gtk::EventControllerMotion.new

  private

    def restart_size_label_timeout
      @size_label_timeout_id.positive?.then do |pending|
        if pending
          GLib::Source.remove(@size_label_timeout_id)
          @size_label_timeout_id = 0
        end
      end

      @size_label_timeout_id = GLib::Timeout.add_seconds(SIZE_LABEL_TIMEOUT) do
        size_label.visible = false
        @size_label_timeout_id = 0
        GLib::Source::REMOVE
      end
    end
end
