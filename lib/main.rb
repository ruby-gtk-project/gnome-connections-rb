# frozen_string_literal: true

require 'adwaita'

require_relative 'settings'
require_relative 'style'
require_relative 'database'
require_relative 'connection'
require_relative 'vnc_connection'
require_relative 'rdp_connection'
require_relative 'spice_connection'
require_relative 'window'
require_relative 'onboarding_dialog'

# App is the application.
#
# Ported from upstream's src/main.vala and src/application.vala: the
# application id and flags, the app.help/app.about/app.quit actions, the about
# dialog, the command-line options, and the ListStore of connections every
# window's collection view is built from.
#
class App
  APP_ID = 'org.gnome.ConnectionsRb'

  # Upstream's icon is its own "<application-id>-symbolic" in its gresource
  # bundle; this port ships no icon theme, so it uses a stock one.
  SYMBOLIC_ICON_NAME = 'computer-symbolic'

  HELP_URI = 'help:gnome-connections'

  COMMENTS = 'A remote desktop client for the GNOME desktop environment'
  COPYRIGHT = '© 2020 Red Hat, Inc.'
  AUTHORS = ['Felipe Borges <felipeborges@gnome.org>'].freeze
  ARTISTS = ['Jakub Steiner <jsteiner@redhat.com>'].freeze
  VERSION = '0.1.0'

  # Upstream's Application.application: the connections, the windows and the
  # dialogs all reach the application through a static reference to it.
  def self.instance = @instance

  def self.instance=(app)
    @instance = app
  end

  attr_reader :settings, :connections, :model

  # app_id/flags are injectable so a test can register a throwaway application
  # rather than talking to the session's real one; present: false builds the
  # whole widget tree without ever mapping a window.
  #
  # Upstream takes ApplicationFlags.HANDLES_COMMAND_LINE and parses its options
  # in the command-line handler. That flag makes GApplication register on the
  # session bus before it will do anything, and on a machine with no session
  # bus — a container, or the headless shell this port is driven in — the
  # process then sits there having done nothing at all. The options are parsed
  # by `parse_arguments` and handed in here instead.
  def initialize(app_id: APP_ID, flags: :default_flags,
                 settings: nil, database: nil, present: true,
                 uri: nil, file: nil, fullscreen: false)
    @app_id = app_id
    @flags = flags
    @settings = settings || Settings.new
    @database = database || Database.default
    @present = present
    @uri = uri
    @file = file
    @fullscreen = fullscreen
    @windows = []
    @connections = []
    @model = Gio::ListStore.new(Connection)
    App.instance = self
  end

  def build
    app.tap do |application|
      ACTIONS.each do |name, accels|
        application.add_action(action(name))
        application.set_accels_for_action("app.#{name}", accels)
      end

      application.signal_connect('startup') { on_startup }
      application.signal_connect('activate') { activate }
      application.signal_connect('shutdown') { on_shutdown }
    end
  end

  def run(argv = ARGV) = app.run([$PROGRAM_NAME, *argv])

  # Upstream's app actions, with the accelerators its shortcuts window lists.
  ACTIONS = {
    'help'  => ['F1'],
    'about' => [],
    'quit'  => ['<Control>q'],
  }.freeze

  def app
    @app ||= Gtk::Application.new(@app_id, @flags)
  end

  def application_id = @app_id

  # Upstream's main_window: the first window the application opened.
  def main_window = @windows.first

  # Upstream's startup: the dark colour scheme is this application's
  # preference, whatever the desktop's is.
  def on_startup
    Adwaita.init
    Adwaita::StyleManager.default.color_scheme = :prefer_dark
    Style.install
  end

  # Upstream's activate: present the window that is already open, otherwise
  # open one, run the first-run tour, and load the saved connections.
  def activate
    main_window.then do |window|
      if window
        window.present
      else
        add_new_window

        if @settings.first_run?
          show_onboarding
          @settings.first_run = false
        end

        load_connections
        apply_startup_options
      end
    end
  end

  def add_new_window
    Window.new(
      app,
      application: @app_id,
      settings:    @settings,
      present:     @present,
    ).tap do |window|
      @windows << window
      window.build
      notify_items_changed
    end
  end

  # Upstream's add_connection: an address already in the database just opens,
  # and a new one is added at the top of the list and opened.
  def add_connection(uri)
    @database.find_connection_by_uri(uri).then do |existing|
      if existing
        open_connection(existing)
      else
        @database.add_connection(uri).then do |connection|
          if connection
            insert_connection(connection)
            open_connection(connection)
          end
        end
      end
    end
  end

  # Upstream's add_connection_from_file: a .vnc file is the one format it
  # imports, and anything else is reported and dropped.
  def add_connection_from_file(file_path)
    if File.extname(file_path).downcase == '.vnc'
      insert_connection(VncConnection.from_vnc_file(file_path))
    else
      warn "Couldn’t open file of unknown mime type #{file_path}"
      nil
    end
  end

  # Upstream's remove_connection: the connection leaves the list at once, and
  # the notification's Undo puts it back. Letting the notification time out is
  # what commits the deletion.
  def remove_connection(connection)
    delete_connection(connection)

    main_window.notifications_bar.display_for_action(
      "Connection to “#{connection.visible_name}” has been deleted",
      'Undo',
      ok:      -> { insert_connection(connection) },
      dismiss: -> { really_remove_connection(connection) },
    )
  end

  # Upstream's load_connections.
  def load_connections
    @database.get_connections.each { |connection| append_connection(connection) }
    notify_items_changed
  end

  # Upstream's open_connection.
  def open_connection(connection)
    main_window.open_connection(connection)
  end

  # Upstream's open: the files named on the command line are imported once the
  # window is up.
  def open_files(paths)
    activate
    paths.each { |path| add_connection_from_file(path) }
  end

  # Upstream's shutdown: every live connection is closed on the way out.
  def on_shutdown
    @connections.each do |connection|
      if connection.connected
        connection.disconnect_it
      end
    end
  end

  # Upstream's quit_app.
  def quit_app
    @windows.each { |window| window.window.visible = false }
    app.quit
  end

  # Upstream's option entries, from src/application.vala:
  #
  #   URL                  the remote desktop to connect to
  #   -F, --file PATH      open a .vnc file at the given PATH
  #   -f, --fullscreen     open in full screen
  #
  # Returns the keyword arguments App.new takes, or an :error to report and
  # exit on — upstream refuses more than one URL the same way.
  def self.parse_arguments(arguments)
    { uri: nil, file: nil, fullscreen: false, error: nil }.tap do |options|
      [].tap do |uris|
        remaining = arguments.dup

        until remaining.empty?
          remaining.shift.then do |argument|
            case argument
            when '-F', '--file' then options[:file] = remaining.shift
            when '-f', '--fullscreen' then options[:fullscreen] = true
            else
              if argument.start_with?('--file=')
                options[:file] = argument.split('=', 2).last
              else
                uris << argument
              end
            end
          end
        end

        if uris.length > 1
          options[:error] = 'Too many command-line arguments specified.'
        end

        options[:uri] = uris.first
      end
    end
  end

  def show_onboarding
    OnboardingDialog.new(main_window&.window).tap do |dialog|
      dialog.build

      if @present
        dialog.present
      end
    end
  end

  # Upstream's show_help, which opens the user documentation.
  def show_help = open_uri(HELP_URI)

  # Upstream's show_about_dialog.
  def show_about_dialog
    about_dialog.present(main_window&.window)
  end

  def about_dialog
    @about_dialog ||= Adwaita::AboutDialog.new.tap do |dialog|
      dialog.application_name = 'Connections'
      dialog.application_icon = SYMBOLIC_ICON_NAME
      dialog.version = VERSION
      dialog.comments = COMMENTS
      dialog.copyright = COPYRIGHT
      dialog.license_type = Gtk::License::GPL_3_0
      dialog.developers = AUTHORS
      dialog.artists = ARTISTS
      dialog.translator_credits = 'translator-credits'
    end
  end

  def open_uri(uri)
    Gio::AppInfo.launch_default_for_uri(uri, nil)
  rescue StandardError => e
    warn "Failed to display #{uri}: #{e.message}"
  end

  private

    def action(name)
      Gio::SimpleAction.new(name).tap do |simple_action|
        simple_action.signal_connect('activate') do
          case name
          when 'help' then show_help
          when 'about' then show_about_dialog
          when 'quit' then quit_app
          end
        end
      end
    end

    # Upstream's command_line, minus the parsing: the URL is connected to, the
    # file is imported, and the window is fullscreened if it was asked for.
    def apply_startup_options
      @uri.then do |uri|
        if uri
          add_connection(uri)
        end
      end

      @file.then do |file|
        if file
          add_connection_from_file(file)
        end
      end

      main_window.fullscreened = @fullscreen
    end

    # Upstream inserts a new connection at the top of the list and appends the
    # ones it loads from the database.
    def insert_connection(connection)
      @connections.unshift(connection)
      @model.insert(0, connection)
      notify_items_changed
      connection
    end

    def append_connection(connection)
      @connections << connection
      @model.append(connection)
      connection
    end

    def delete_connection(connection)
      @connections.index(connection).then do |position|
        if position
          @connections.delete_at(position)
          @model.remove(position)
          notify_items_changed
        end
      end
    end

    # Upstream's really_remove: the connection is closed, its credentials are
    # dropped and the database forgets it.
    def really_remove_connection(connection)
      connection.disconnect_it
      connection.delete_auth_credentials
      @database.delete_connection(connection)
    end

    # Upstream's model.items_changed, which every window listens to.
    def notify_items_changed
      @windows.each { |window| window.items_changed(@connections) }
    end
end
