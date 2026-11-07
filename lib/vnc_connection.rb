# frozen_string_literal: true

require 'adwaita'

require_relative 'connection'

# VncConnection is a connection over RFB.
#
# Ported from upstream's src/vnc-connection.vala: the default port, the
# view-only/local-pointer/audio/bandwidth/scale-mode properties the VNC
# preferences window edits, the three ways a connection is created (from a
# uuid in the database, from a URL, and by importing a .vnc file), and the
# three scale modes.
#
# Upstream's display widget is a Vnc.Display from gtk-vnc, which speaks RFB
# itself. gtk-vnc ships no GObject-introspection typelib in this port's
# development environment, so there is no widget here that can talk to a VNC
# server: `connect_it` reports through `on_connection_error`, the same path
# upstream takes when a server refuses a connection, and the display widget
# states which library is missing. Everything else — the model, its
# persistence, the preferences and the scale modes — is the upstream
# behaviour.
#
class VncConnection < Connection
  type_register

  PROTOCOL = 'vnc'
  DEFAULT_PORT = 5900

  # Upstream's default is the string "hight-quality", which matches none of the
  # ids in its own bandwidth combo; "high-quality" is the id it meant.
  DEFAULT_BANDWIDTH = 'high-quality'
  DEFAULT_SCALE_MODE = 'fit-window'

  LIBRARY = 'gtk-vnc'
  UNAVAILABLE = 'VNC is unavailable: this build has no gtk-vnc typelib'

  connection_property :view_only
  connection_property :show_local_pointer
  connection_property :enable_audio
  connection_property :bandwidth
  connection_property :scale_mode

  def self.persisted_properties
    BASE_PROPERTIES + %w[view-only show-local-pointer enable-audio bandwidth scale-mode]
  end

  # Upstream's VncConnection.from_uri.
  def self.from_uri(uri) = new.tap { |connection| connection.uri = uri }

  # Upstream's VncConnection.from_vnc_file: a .vnc file is a keyfile with a
  # [Connection] group. Every key is optional, and a missing one leaves the
  # default in place.
  #
  # Upstream reads the password under the key "Password " — with a trailing
  # space — which never matches; this reads "Password".
  def self.from_vnc_file(file_path)
    new.tap do |connection|
      GLib::KeyFile.new.then do |key_file|
        begin
          key_file.load_from_file(file_path, GLib::KeyFile::NONE)
        rescue GLib::Error, GLib::KeyFileError => e
          warn "Couldn’t parse the file: #{e.message}"
        end

        connection.import_vnc_keys(key_file)

        # import_vnc_keys only ever assigns the keys the .vnc file actually
        # has, each of which saves itself individually; "protocol" is never
        # among them (the file has no such key — vnc is implied by the class),
        # so without this a connection imported from a file with only, say, a
        # Host key would never get a "protocol" row written to connections.db
        # at all. The next load would then find a group with no protocol key,
        # log "Unknown protocol defined", and the imported connection would
        # silently vanish. Saving every persisted property once, outright,
        # covers that.
        connection.save
      end
    end
  end

  VNC_FILE_KEYS = {
    'Host'     => :host,
    'Port'     => :port,
    'Username' => :username,
    'Password' => :password,
  }.freeze

  def initialize(uuid: nil)
    super

    @view_only = false
    @show_local_pointer = false
    @enable_audio = true
    @bandwidth = DEFAULT_BANDWIDTH
    @scale_mode = DEFAULT_SCALE_MODE
    @scaling = true
    @allow_resize = false

    on_property_changed(:scale_mode) { scale }
    on_authentication_complete { connect_it }
  end

  # Translators: %s is a VNC file key.
  def import_vnc_keys(key_file)
    VNC_FILE_KEYS.each do |key, property|
      begin
        if property == :port
          self.port = key_file.get_integer('Connection', key)
        else
          public_send(:"#{property}=", key_file.get_string('Connection', key))
        end
      rescue GLib::Error, GLib::KeyFileError
        warn "VNC File is missing key “#{key}”"
      end
    end
  end

  attr_reader :allow_resize

  # The last key combination handed to send_keys, so the display's key-input
  # menu is observable without a remote server.
  attr_reader :sent_keys

  # Upstream packs its Vnc.Display into a sidecar window so the widget always
  # has a realized surface; here the display only ever needs detaching from
  # the display view that showed it last.
  def widget = display

  def dispose_display
    display.parent.then do |parent|
      if parent
        display.unparent
      end
    end
  end

  def display
    @display ||= Adwaita::StatusPage.new.tap do |page|
      page.icon_name = 'network-wired-symbolic'
      page.title = 'VNC Unavailable'
      page.description = "This build of Connections has no #{LIBRARY} support, " \
                         'so VNC displays cannot be shown.'
      page.vexpand = true
      page.hexpand = true
    end
  end

  # Upstream reads the thumbnail off the live display; without one there is no
  # image to scale into the collection tile or to save as a screenshot, and
  # both callers already handle a connection that has no thumbnail.
  def thumbnail = nil

  def scaling = @scaling

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

  # Upstream's scale: the scale mode decides whether the display scales to the
  # window, keeps its original size, or asks the server to resize.
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
