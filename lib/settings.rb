# frozen_string_literal: true

require 'json'
require 'fileutils'

# Settings holds the same keys as upstream's org.gnome.Connections GSettings
# schema (data/org.gnome.Connections.gschema.xml): "first-run" and
# "window-size".
#
# Upstream reads them through GLib.Settings, which needs a compiled schema
# installed into the system's glib-2.0/schemas directory. Requiring an install
# step before the app can run from a checkout is worse than the alternative, so
# the same keys, defaults and semantics are backed by a small JSON file under
# XDG_CONFIG_HOME instead.
#
class Settings
  DEFAULTS = {
    'first-run'   => true,
    'window-size' => [1024, 768],
  }.freeze

  def initialize(path: nil)
    @path = path || default_path
    @values = DEFAULTS.merge(read)
  end

  def [](key) = @values.fetch(key.to_s, DEFAULTS[key.to_s])

  def []=(key, value)
    @values[key.to_s] = value
    write
    value
  end

  def location = @path

  def first_run? = self['first-run'] == true

  def first_run=(value)
    self['first-run'] = value
  end

  # Upstream stores the geometry as a GVariant "(ii)" and only restores it when
  # the tuple really has two members; a JSON array is checked the same way.
  def window_size
    self['window-size'].then do |size|
      if size.is_a?(Array) && size.length == 2
        size.map(&:to_i)
      else
        DEFAULTS['window-size']
      end
    end
  end

  def window_size=(size)
    self['window-size'] = size.map(&:to_i)
  end

  # Upstream's Window constructor: restore the recorded size as the default
  # size, so the window opens the way the user left it.
  def apply_to(window)
    window_size.then { |width, height| window.set_default_size(width, height) }
  end

  # Upstream's save_window_geometry skips the save while maximized, so the
  # restored size is the one the user actually chose.
  def remember(window)
    (window.maximized? || window.fullscreened?).then do |filling_the_screen|
      unless filling_the_screen
        self.window_size = [window.default_width, window.default_height]
      end
    end
  end

  private

    def default_path
      File.join(
        ENV.fetch('XDG_CONFIG_HOME', File.expand_path('~/.config')),
        'ruby-connections',
        'settings.json',
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

    def write
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.pretty_generate(@values))
    end
end
