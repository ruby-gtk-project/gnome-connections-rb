# frozen_string_literal: true

require 'adwaita'

require_relative 'connection'

# SpiceConnection is a connection over SPICE.
#
# Ported from upstream's src/spice-connection.vala: the default port, the
# audio and scale-mode properties the SPICE preferences window edits, and the
# channel-event handling that turns an authentication error into an
# authentication prompt.
#
# SPICE is optional upstream — src/meson.build guards the class behind
# HAS_SPICE, and the assistant hides its SPICE radio button when the build
# lacks it. `SpiceConnection.available?` is this port's HAS_SPICE: spice-gtk
# ships no GObject-introspection typelib in this port's development
# environment, so there is no widget here that can talk to a SPICE server.
# `connect_it` reports through `on_connection_error`, the same path upstream
# takes when a session closes with an error, and the display widget states
# which library is missing.
#
class SpiceConnection < Connection
  type_register

  PROTOCOL = 'spice'
  DEFAULT_PORT = 3128

  DEFAULT_SCALE_MODE = 'fit-window'

  LIBRARY = 'spice-gtk'
  UNAVAILABLE = 'SPICE is unavailable: this build has no spice-gtk typelib'

  # Upstream's HAS_SPICE. The protocol is offered in the assistant and the
  # database only when the build can speak it.
  def self.available? = false

  connection_property :enable_audio
  connection_property :scale_mode

  def self.persisted_properties = BASE_PROPERTIES + %w[enable-audio scale-mode]

  # Upstream's SpiceConnection.from_uri.
  def self.from_uri(uri) = new.tap { |connection| connection.uri = uri }

  attr_reader :resize_guest, :sent_keys

  def initialize(uuid: nil)
    super

    @enable_audio = true
    @scale_mode = DEFAULT_SCALE_MODE
    @scaling = true
    @resize_guest = false

    on_property_changed(:scale_mode) { scale }
    on_authentication_complete { connect_it }
  end

  def widget = display

  def display
    @display ||= Adwaita::StatusPage.new.tap do |page|
      page.icon_name = 'computer-symbolic'
      page.title = 'SPICE Unavailable'
      page.description = "This build of Connections has no #{LIBRARY} support, " \
                         'so SPICE displays cannot be shown.'
      page.vexpand = true
      page.hexpand = true
    end
  end

  # Upstream reads the thumbnail off the live display; both callers already
  # handle a connection that has no thumbnail.
  def thumbnail = nil

  # Upstream reports a disconnected SPICE connection as scaling, whatever the
  # display says.
  def scaling
    @connected.then do |live|
      if live
        @scaling
      else
        true
      end
    end
  end

  def scaling=(value)
    @scaling = value
    property_changed(:scaling)
  end

  def connect_it
    self.connected = false
    on_connection_error(UNAVAILABLE)
  end

  def disconnect_it
    self.connected = false
  end

  def send_keys(keyvals)
    @sent_keys = keyvals
  end

  # Upstream's dispose_display is empty for SPICE.
  def dispose_display = nil

  # Upstream's main_event: the main channel's events decide whether the session
  # is closed, needs a password, or has an error worth reporting.
  def handle_channel_event(event)
    case event
    when :closed then disconnect_it
    when :error_auth
      self.need_password = true
      handle_auth
      disconnect_it
    when :error_connect, :error_io, :error_link, :error_tls
      on_connection_error("main SPICE channel error: #{event}")
      disconnect_it
    when :opened then emit_show
    end
  end

  # Upstream's scale.
  def scale
    @scaling = false
    @resize_guest = false

    case scale_mode
    when 'resize-desktop' then @resize_guest = true
    when 'fit-window' then @scaling = true
    when 'original' then @scaling = false
    end

    property_changed(:scaling)
  end
end
