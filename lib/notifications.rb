# frozen_string_literal: true

require 'adwaita'

# Notification is one in-app notification: a message, an optional action
# button, and a close button.
#
# Ported from upstream's src/notifications.vala (the Notification class) and
# src/ui/notification.ui. It reveals itself as soon as it is built and
# dismisses itself after six seconds unless the action is taken first.
#
class Notification
  attr_reader :message

  def initialize(message, ok_label: nil, ok: nil, dismiss: nil,
                 timeout: NotificationsBar::DEFAULT_TIMEOUT)
    @message = message
    @ok_label = ok_label
    @ok_func = ok
    @dismiss_func = dismiss
    @timeout = timeout
    @timeout_id = 0
    @dismissed_handlers = []
  end

  def on_dismissed(&block) = @dismissed_handlers << block

  def build
    revealer.tap do |rev|
      rev.child = grid

      grid.tap do |g|
        g.attach(
          message_label,
          0,
          0,
          1,
          1,
        )
        g.attach(
          ok_button,
          1,
          0,
          1,
          1,
        )
        g.attach(
          close_button,
          2,
          0,
          1,
          1,
        )

        ok_button.tap do |button|
          button.visible = !@ok_label.nil?
          button.signal_connect('clicked') { accept }
        end

        close_button.signal_connect('clicked') { dismiss }
      end

      rev.reveal_child = true

      @timeout_id = GLib::Timeout.add_seconds(@timeout) do
        @timeout_id = 0
        dismiss
        GLib::Source::REMOVE
      end
    end
  end

  # Upstream's ok_button.clicked handler: run the action, hide, and report the
  # notification as dismissed without running the dismiss action — taking the
  # action is what cancels it.
  def accept
    @ok_func&.call
    revealer.reveal_child = false
    cancel_timeout
    @dismissed_handlers.each(&:call)
  end

  # Upstream's dismiss: report it, hide it, and run the dismiss action, which
  # is what commits a deletion the undo button would have cancelled.
  def dismiss
    @dismissed_handlers.each(&:call)
    revealer.reveal_child = false
    @dismiss_func&.call
    cancel_timeout
  end

  def revealer
    @revealer ||= Gtk::Revealer.new.tap do |rev|
      rev.valign = :start
    end
  end

  def grid
    @grid ||= Gtk::Grid.new.tap do |g|
      g.margin_start = 12
      g.margin_end = 12
      g.column_spacing = 12
      g.valign = :center
      g.halign = :center
      g.add_css_class('app-notification')
    end
  end

  def message_label = @message_label ||= Gtk::Label.new(@message)

  def ok_button
    @ok_button ||= Gtk::Button.new(label: @ok_label.to_s).tap do |button|
      button.halign = :end
    end
  end

  def close_button
    @close_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'window-close-symbolic'
      button.add_css_class('flat')
    end
  end

  private

    def cancel_timeout
      @timeout_id.positive?.then do |pending|
        if pending
          GLib::Source.remove(@timeout_id)
          @timeout_id = 0
        end
      end
    end
end

# NotificationsBar holds the notification currently on screen.
#
# Ported from upstream's src/notifications.vala (the NotificationsBar class):
# an Adwaita::Bin pinned to the top centre of the window's overlay, showing at
# most one notification at a time.
#
class NotificationsBar
  DEFAULT_TIMEOUT = 6

  def build = bin

  def active_notification = @active_notification

  def active_notification=(notification)
    @active_notification = notification
    if notification
      bin.child = notification.build
    else
      bin.child = nil
    end
  end

  # Upstream's display_for_error.
  def display_for_error(message)
    self.active_notification = Notification.new(message)
  end

  # Upstream's display_for_action: the OK button runs `ok`, and letting the
  # notification time out runs `dismiss` instead.
  def display_for_action(message, ok_label, ok: nil, dismiss: nil)
    Notification.new(message, ok_label: ok_label, ok: ok, dismiss: dismiss).tap do |notification|
      notification.on_dismissed { @active_notification = nil }
      self.active_notification = notification
    end
  end

  # Upstream's dismiss, which the window calls as it closes so a pending
  # deletion is committed rather than lost.
  def dismiss
    @active_notification.then do |notification|
      if notification
        notification.dismiss
        self.active_notification = nil
      end
    end
  end

  def bin
    @bin ||= Adwaita::Bin.new.tap do |widget|
      widget.valign = :start
      widget.halign = :center
      widget.add_css_class('transparent-bg')
    end
  end
end
