# frozen_string_literal: true

require 'adwaita'
require 'uri'
require 'fileutils'

require_relative 'connection'
require_relative 'vnc_connection'
require_relative 'rdp_connection'
require_relative 'spice_connection'

# Database is the connection store.
#
# A direct port of upstream's src/database.vala: a GKeyFile at
# $XDG_CONFIG_HOME/connections.db, one group per connection keyed by its uuid,
# one key per property. Loading a connection reads its protocol first, builds
# the matching subclass, and then sets every other key onto it.
#
class Database
  FILENAME = 'connections.db'

  # Upstream's Database.get_default.
  def self.default = @default ||= new

  # Upstream's protocol switch, in both directions: the keyfile's "protocol"
  # value picks the class, and the URL's scheme picks the constructor. SPICE is
  # only offered when the build can speak it, as upstream's #if HAS_SPICE does.
  def self.protocols
    {
      'vnc' => VncConnection,
      'rdp' => RdpConnection,
    }.tap do |protocols|
      if SpiceConnection.available?
        protocols['spice'] = SpiceConnection
      end
    end
  end

  def initialize(path: nil)
    @path = path || default_path
    @keyfile = GLib::KeyFile.new
  end

  def location = @path

  # Upstream's get_connections.
  def get_connections
    load_keyfile

    @keyfile.groups.filter_map { |uuid| get_connection(uuid) }
  end

  # Upstream's get_connection: nothing to build without a group, and nothing to
  # build for a protocol this build does not know.
  def get_connection(uuid)
    load_keyfile

    @keyfile.has_group?(uuid).then do |known|
      if known
        self.class.protocols[get_string(uuid, 'protocol')].then do |klass|
          if klass
            klass.new(uuid: uuid).while_loading { |connection| load_properties(connection) }
          else
            warn "Unknown protocol defined for #{uuid}"
            nil
          end
        end
      end
    end
  end

  # Upstream's find_connection_by_uri: a connection already in the database
  # matching protocol, host and — when the URL names one — port.
  def find_connection_by_uri(uri)
    URI.parse(uri).then do |address|
      get_connections.find do |connection|
        connection.protocol == address.scheme &&
          connection.host == address.host &&
          (address.port.nil? || connection.port == address.port)
      end
    end
  rescue URI::InvalidURIError => e
    warn "Failed to parse URI: #{uri} (#{e.message})"
    nil
  end

  # Upstream's add_connection: build the connection the URL's scheme asks for
  # and save it. An unknown scheme adds nothing.
  def add_connection(uri)
    uri_scheme(uri).then do |scheme|
      self.class.protocols[scheme].then do |klass|
        if klass
          klass.from_uri(uri).tap(&:save)
        else
          warn "Failed to add '#{uri}': unknown protocol"
          nil
        end
      end
    end
  end

  # Upstream's delete_connection.
  def delete_connection(connection)
    load_keyfile

    begin
      @keyfile.remove_group(connection.uuid)
    rescue GLib::Error, GLib::KeyFileError => e
      warn "Failed to delete '#{connection.uuid}': #{e.message}"
    end

    save_keyfile
  end

  # Upstream's save_property: one property, written in the keyfile type that
  # matches the value's own type.
  def save_property(connection, property_name)
    load_keyfile

    connection.public_send(reader_for(property_name)).then do |value|
      case value
      when nil then @keyfile.set_string(connection.uuid, property_name, '')
      when String then @keyfile.set_string(connection.uuid, property_name, value)
      when true, false then @keyfile.set_boolean(connection.uuid, property_name, value)
      when Integer then @keyfile.set_integer(connection.uuid, property_name, value)
      else warn "Unhandled property #{property_name} type, value: #{value.inspect}"
      end
    end

    save_keyfile
  end

  private

    def default_path
      File.join(ENV.fetch('XDG_CONFIG_HOME', File.expand_path('~/.config')), FILENAME)
    end

    def reader_for(property_name) = property_name.to_s.tr('-', '_')

    def uri_scheme(uri)
      URI.parse(uri).scheme
    rescue URI::InvalidURIError
      nil
    end

    # Upstream's load_keyfile: create the file 0600 when it is not there yet,
    # then read it.
    def load_keyfile
      unless File.exist?(@path)
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, '')
        File.chmod(0o600, @path)
      end

      begin
        @keyfile.load_from_file(
          @path,
          GLib::KeyFile::KEEP_COMMENTS | GLib::KeyFile::KEEP_TRANSLATIONS,
        )
      rescue GLib::Error, GLib::KeyFileError => e
        warn "Failed to load database: #{e.message}"
      end
    end

    def save_keyfile
      File.write(@path, @keyfile.to_data)
      true
    rescue SystemCallError => e
      warn "Failed to save database: #{e.message}"
      false
    end

    # Upstream's load_properties: every key in the group that the connection
    # has a writer for.
    def load_properties(connection)
      @keyfile.get_keys(connection.uuid).each do |property_name|
        load_property(connection, property_name)
      end
    rescue GLib::Error, GLib::KeyFileError => e
      warn "Failed to load connection properties: #{e.message}"
    end

    # Upstream's load_property reads the keyfile in the property's declared
    # type; here the property's current value is what says which type that is.
    def load_property(connection, property_name)
      reader_for(property_name).then do |reader|
        if connection.respond_to?(reader) && connection.respond_to?(:"#{reader}=")
          connection.public_send(
            :"#{reader}=",
            typed_value(connection.uuid, property_name, connection.public_send(reader)),
          )
        end
      end
    end

    def typed_value(uuid, property_name, current)
      case current
      when true, false then get_boolean(uuid, property_name)
      when Integer then get_integer(uuid, property_name, current)
      else get_string(uuid, property_name)
      end
    end

    # Upstream's get_string/get_boolean: a missing key is not an error, it just
    # means the default stands.
    def get_string(group, key)
      @keyfile.get_string(group, key)
    rescue GLib::Error, GLib::KeyFileError
      ''
    end

    def get_boolean(group, key)
      @keyfile.get_boolean(group, key)
    rescue GLib::Error, GLib::KeyFileError
      false
    end

    def get_integer(group, key, default)
      @keyfile.get_integer(group, key)
    rescue GLib::Error, GLib::KeyFileError
      default
    end
end
