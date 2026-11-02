# frozen_string_literal: true

require 'adwaita'

require_relative 'connection'

# RdpConnection is a connection over RDP.
#
# Ported from upstream's src/rdp-connection.vala: the default port, the
# scale-mode property, the resize-supported flag the preferences window grows
# its "Resize desktop" item from, and the fact that RDP always asks for a
# username, a password and a domain before it connects.
#
# Upstream's display widget is a Frdp.Display from gtk-frdp, which speaks RDP
# itself and raises the certificate-verification and authentication signals
# this class forwards to the dialogs window. gtk-frdp ships no
# GObject-introspection typelib in this port's development environment, so
# there is no widget here that can talk to an RDP server: `connect_it` reports
# through `on_connection_error`, the same path upstream takes when a server
# refuses a connection, and the display widget states which library is
# missing. The certificate and authentication hooks are the inherited ones, so
# a backend that can raise them has somewhere to raise them to.
#
class RdpConnection < Connection
  type_register

  PROTOCOL = 'rdp'
  DEFAULT_PORT = 3389

  DEFAULT_SCALE_MODE = 'fit-window'

  LIBRARY = 'gtk-frdp'
  UNAVAILABLE = 'RDP is unavailable: this build has no gtk-frdp typelib'

  connection_property :scale_mode

  def self.persisted_properties = BASE_PROPERTIES + %w[scale-mode]

  # Upstream's RdpConnection.from_uri.
  def self.from_uri(uri) = new.tap { |connection| connection.uri = uri }

  # Upstream's resize_supported is set from the display's own property, so it
  # is read-only to everyone but the backend.
  attr_reader :resize_supported, :allow_resize, :sent_keys

  def initialize(uuid: nil)
    super

    @scale_mode = DEFAULT_SCALE_MODE
    @resize_supported = false
    @scaling = true
    @allow_resize = false
    @connecting = false

    self.need_username = true
    self.need_password = true
    self.need_domain = true

    self.certificate_verified = false
    self.certificate_change_verified = false

    on_property_changed(:scale_mode) { scale }
  end

  # Upstream's update_resize_supported, which mirrors the display's property
  # onto the connection so the preferences window can watch one object.
  def resize_supported=(value)
    @resize_supported = value
    property_changed(:resize_supported)
  end

  def widget = display

  def display
    @display ||= Adwaita::StatusPage.new.tap do |page|
      page.icon_name = 'network-wired-symbolic'
      page.title = 'RDP Unavailable'
      page.description = "This build of Connections has no #{LIBRARY} support, " \
                         'so RDP displays cannot be shown.'
      page.vexpand = true
      page.hexpand = true
    end
  end

  # Upstream draws the widget into a Cairo surface to get a thumbnail; a
  # display that was never connected has nothing to draw, and both callers
  # already handle a connection that has no thumbnail.
  def thumbnail = nil

  # Upstream reports a disconnected RDP connection as scaling, whatever the
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

  # Upstream guards against re-entering connect_it while a connection attempt
  # is already in flight.
  def connect_it
    @connecting.then do |in_flight|
      unless in_flight
        @connecting = true
        self.connected = false
        on_connection_error(UNAVAILABLE)
        @connecting = false
      end
    end
  end

  def disconnect_it
    self.connected = false
  end

  # Upstream's send_keys is empty for RDP: gtk-frdp has no key-injection API.
  def send_keys(keyvals)
    @sent_keys = keyvals
  end

  # Upstream's dispose_display is empty for RDP, because its display is never
  # packed into a sidecar window.
  def dispose_display = nil

  # Upstream's scale.
  def scale
    @scaling = false
    @allow_resize = false

    case scale_mode
    when 'resize-desktop' then @allow_resize = true
    when 'fit-window' then @scaling = true
    when 'original' then @scaling = false
    end

    property_changed(:scaling)
  end
end
