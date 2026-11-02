# frozen_string_literal: true

require 'adwaita'
require 'json'
require 'uri'
require 'fileutils'
require 'securerandom'

# Credentials is the connection credential store.
#
# Upstream's connection.vala keeps the username, password and domain in the
# login keyring through libsecret, under a schema of its own keyed by the
# connection uuid. libsecret has no GObject-introspection typelib in this
# port's development environment, so the same three fields are kept in a file
# of their own — created 0600, never written into the connection database, and
# holding exactly what upstream's keyring entry holds.
#
class Credentials
  def self.default = @default ||= new

  def initialize(path: nil)
    @path = path || default_path
  end

  def location = @path

  def lookup(uuid) = read.fetch(uuid, {})

  def store(uuid, fields)
    read.then do |all|
      all[uuid] = fields.compact
      write(all)
    end
  end

  def delete(uuid)
    read.then do |all|
      all.delete(uuid)
      write(all)
    end
  end

  private

    def default_path
      File.join(
        ENV.fetch('XDG_CONFIG_HOME', File.expand_path('~/.config')),
        'ruby-connections',
        'credentials.json',
      )
    end

    def read
      if File.exist?(@path)
        JSON.parse(File.read(@path))
      else
        {}
      end
    rescue JSON::ParserError => e
      warn "Error parsing #{@path}: #{e.message}"
      {}
    end

    def write(all)
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.pretty_generate(all))
      File.chmod(0o600, @path)
    end
end

# Connection is the abstract remote-desktop connection.
#
# Ported from upstream's src/connection.vala. It holds everything that is not
# protocol specific: the uuid a connection is stored under, the address split
# into protocol/host/port, the display name, the authentication and certificate
# hooks the protocol backends call into, the screenshot action, and the
# save-on-change behaviour that writes every property back to the database.
#
# Upstream is a GObject and leans on GObject properties for two things: the
# `notify` signal (which it connects to `save`, so every property change is
# persisted) and `bind_property` (which the preferences windows use to bind a
# widget to a connection property). Neither is available for properties
# declared in Ruby, so `connection_property` below defines accessors that
# notify explicit observers and save, and the preferences windows bind against
# those observers.
#
class Connection < GLib::Object
  type_register

  # Subclasses override both.
  PROTOCOL = ''
  DEFAULT_PORT = 0

  # The keys every connection is stored under, in upstream's spelling: the
  # keyfile keys are GObject property names, which are dash separated.
  BASE_PROPERTIES = %w[protocol host port display-name].freeze

  # Declares a property that notifies its observers and saves itself, the way
  # upstream's `notify.connect (save)` does for every GObject property.
  def self.connection_property(name)
    attr_reader(name)

    define_method(:"#{name}=") do |value|
      instance_variable_set(:"@#{name}", value)
      property_changed(name)
      save(name)
    end
  end

  # The properties this class persists. Subclasses add their own.
  def self.persisted_properties = BASE_PROPERTIES

  connection_property :host
  connection_property :port
  connection_property :protocol
  connection_property :display_name

  attr_reader :uuid
  attr_accessor :connected, :need_username, :need_password, :need_domain
  attr_accessor :certificate_verified, :certificate_change_verified

  def initialize(uuid: nil)
    super()

    @uuid = uuid || SecureRandom.uuid
    @host = ''
    @port = self.class::DEFAULT_PORT
    @protocol = self.class::PROTOCOL
    @display_name = ''
    @connected = false
    @need_username = false
    @need_password = false
    @need_domain = false
    @certificate_verified = false
    @certificate_change_verified = false
    @observers = {}
    @saving = false
  end

  # Upstream joins the parts back into a URI with GLib.Uri.join; the port is
  # always present because every subclass carries a default for it.
  def uri = "#{protocol}://#{host}:#{port}"

  def uri=(value)
    URI.parse(value).then do |address|
      self.protocol = address.scheme
      self.host = address.host.to_s
      self.port = address.port || port
    end
  rescue URI::InvalidURIError => e
    warn "Failed to parse URI: #{value} (#{e.message})"
  end

  # Upstream's get_visible_name: the display name when the user set one,
  # otherwise the address.
  def visible_name
    display_name.to_s.empty?.then do |unnamed|
      if unnamed
        uri
      else
        display_name
      end
    end
  end

  # Observers stand in for the GObject notify signal: the collection view's
  # tiles and the preferences windows both want to hear about a property they
  # do not own.
  def on_property_changed(name = nil, &block)
    observers_for(name) << block
  end

  def property_changed(name)
    [observers_for(name), observers_for(nil)].each do |observers|
      observers.each { |observer| observer.call(name) }
    end
  end

  # Upstream's `show` signal: the protocol backend raises it once the remote
  # display has something to draw.
  def on_show(&block) = on_property_changed(:show, &block)
  def emit_show = property_changed(:show)

  # Upstream's authentication_complete signal.
  def on_authentication_complete(&block) = on_property_changed(:authentication_complete, &block)
  def authentication_complete = property_changed(:authentication_complete)

  # Upstream's certificate_verification_complete signal.
  def on_certificate_verification_complete(&block)
    on_property_changed(:certificate_verification_complete, &block)
  end

  def certificate_verification_complete
    property_changed(:certificate_verification_complete)
  end

  def on_certificate_change_verification_complete(&block)
    on_property_changed(:certificate_change_verification_complete, &block)
  end

  def certificate_change_verification_complete
    property_changed(:certificate_change_verification_complete)
  end

  # Upstream's save: a property change writes that one key back to the
  # database, except for the credentials, which go to the credential store
  # rather than into the database in plain text.
  def save(property_name = nil)
    @saving.then do |loading|
      unless loading
        if %w[username password domain].include?(property_name.to_s)
          store_auth_credentials
        else
          save_to_database(property_name)
        end
      end
    end
  end

  # The database sets every property it read back onto the connection; without
  # this each of those writes would be saved straight back out again.
  def while_loading
    @saving = true
    yield self
    @saving = false
    self
  end

  # Credentials. Upstream keeps these in the login keyring through libsecret;
  # see Credentials for why this port keeps them in a file of its own.
  attr_reader :username, :password, :domain

  %i[username password domain].each do |name|
    define_method(:"#{name}=") do |value|
      instance_variable_set(:"@#{name}", value)
      property_changed(name)
      save(name)
    end
  end

  # Upstream's handle_auth: ask the protocol backend's credentials of the
  # keyring first, and only prompt when the keyring has nothing to offer.
  def handle_auth
    (@need_username || @need_password).then do |needs_anything|
      if needs_anything
        if credentials_complete?
          authentication_complete
        else
          load_auth_credentials
        end
      end
    end
  end

  def delete_auth_credentials
    credentials.delete(uuid)
  end

  # Upstream's on_connection_error_cb: the notification bar reports the reason
  # and the window falls back to the collection view.
  def on_connection_error(reason)
    App.instance.then do |app|
      app.main_window.notifications_bar.display_for_error(reason)
      app.main_window.show_collection_view
    end
  end

  # Upstream's auth_failed: drop the stored credentials so the next attempt
  # prompts again, and report the failure.
  def auth_failed(reason)
    disconnect_it
    delete_auth_credentials
    @username = @password = @domain = nil

    App.instance.then do |app|
      app.main_window.show_collection_view
      app.main_window.notifications_bar.display_for_error("Authentication failed: #{reason}")
    end
  end

  def handle_certificate_verification(_subject, _issuer, fingerprint)
    App.instance.main_window.dialogs_window.show_certificate_verification(
      visible_name,
      fingerprint,
    ) do |verified|
      self.certificate_verified = verified
      certificate_verification_complete
    end
  end

  def handle_certificate_change_verification(_new_subject, _new_issuer, new_fingerprint,
                                             _old_subject, _old_issuer, _old_fingerprint)
    App.instance.main_window.dialogs_window.show_certificate_change_verification(
      visible_name,
      new_fingerprint,
    ) do |verified|
      self.certificate_change_verified = verified
      certificate_change_verification_complete
    end
  end

  # Upstream's take_screenshot: write the current display contents into the
  # user's Pictures directory, offer to open the file, and flash the display.
  def take_screenshot
    thumbnail.then do |pixbuf|
      if pixbuf
        screenshot_path.then do |path|
          pixbuf.save(path, 'png')
          notify_screenshot_taken(path)
        end
        flash_display
      end
    end
  rescue StandardError => e
    warn "Failed to take screenshot #{e.message}"
  end

  # Upstream's flash_display: the display's parent wears the .flash class for
  # the length of the animation in style.css.
  def flash_display
    widget.parent.then do |parent|
      if parent
        parent.add_css_class('flash')
        GLib::Timeout.add(200) do
          parent.remove_css_class('flash')
          GLib::Source::REMOVE
        end
      end
    end
  end

  # Abstract: the protocol backends supply the display widget and the
  # transport, and say how a thumbnail of the display is obtained.
  def widget = raise(NotImplementedError, "#{self.class} must provide a display widget")
  def thumbnail = raise(NotImplementedError, "#{self.class} must provide a thumbnail")
  def scaling = raise(NotImplementedError, "#{self.class} must provide scaling")

  def scaling=(_value)
    raise(NotImplementedError, "#{self.class} must provide scaling=")
  end

  def connect_it = raise(NotImplementedError, "#{self.class} must provide connect_it")
  def disconnect_it = raise(NotImplementedError, "#{self.class} must provide disconnect_it")
  def dispose_display = raise(NotImplementedError, "#{self.class} must provide dispose_display")
  def send_keys(_keyvals) = raise(NotImplementedError, "#{self.class} must provide send_keys")

  private

    def observers_for(name)
      @observers[name&.to_sym] ||= []
    end

    def credentials = Credentials.default

    def credentials_complete?
      [
        [@need_username, @username],
        [@need_password, @password],
        [@need_domain, @domain],
      ].none? { |needed, value| needed && value.nil? }
    end

    # Upstream's Secret.password_lookup callback: use what the store has, and
    # prompt through the dialogs window when it has nothing.
    def load_auth_credentials
      credentials.lookup(uuid).then do |stored|
        if stored.empty?
          prompt_for_auth_credentials
        else
          @username = stored['username'] || @username
          @password = stored['password'] || @password
          @domain = stored['domain'] || @domain
          authentication_complete
        end
      end
    end

    def prompt_for_auth_credentials
      App.instance.main_window.dialogs_window.show_authentication(
        visible_name,
        need_username: @need_username,
        need_password: @need_password,
        need_domain:   @need_domain,
      ) do |username, password, domain|
        { username: username, password: password, domain: domain }.each do |name, value|
          unless value.to_s.empty?
            instance_variable_set(:"@#{name}", value)
          end
        end

        App.instance.open_connection(self)
        authentication_complete
      end
    end

    # Upstream's store_auth_credentials: nothing is stored until there is a
    # password to store.
    def store_auth_credentials
      @password.to_s.empty?.then do |no_password|
        unless no_password
          credentials.store(
            uuid,
            'username' => @username,
            'domain'   => @domain,
            'password' => @password,
          )
        end
      end
    end

    def save_to_database(property_name)
      Database.default.then do |database|
        if property_name
          database.save_property(self, property_name.to_s.tr('_', '-'))
        else
          self.class.persisted_properties.each { |name| database.save_property(self, name) }
        end
      end
    end

    # Translators: %s => the timestamp of when the screenshot was taken.
    def screenshot_path
      Time.now.strftime('%Y-%m-%d %H-%M-%S').then do |timestamp|
        File.join(pictures_directory, "Screenshot from #{timestamp}.png")
      end
    end

    def pictures_directory
      (ENV['XDG_PICTURES_DIR'] || File.expand_path('~/Pictures')).tap do |path|
        FileUtils.mkdir_p(path)
      end
    end

    # Translators: Open is a verb.
    def notify_screenshot_taken(path)
      App.instance.main_window.notifications_bar.display_for_action(
        'Screenshot taken',
        'Open',
        ok: -> { App.instance.open_uri(Gio::File.new_for_path(path).uri) },
      )
    end
end
