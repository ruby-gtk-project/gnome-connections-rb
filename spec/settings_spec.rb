# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Unit coverage for Settings (lib/settings.rb), the JSON-file stand-in for
# upstream's org.gnome.Connections GSettings schema.
RSpec.describe Settings do
  around do |example|
    Dir.mktmpdir("gnome-connections-rb-settings") do |dir|
      @path = File.join(dir, "settings.json")
      example.run
    end
  end

  subject(:settings) { described_class.new(path: @path) }

  it "defaults first-run to true" do
    expect(settings.first_run?).to be(true)
  end

  it "defaults window-size to 1024x768" do
    expect(settings.window_size).to eq([1024, 768])
  end

  it "persists first_run= across instances backed by the same file" do
    settings.first_run = false

    expect(described_class.new(path: @path).first_run?).to be(false)
  end

  it "persists window_size= across instances backed by the same file" do
    settings.window_size = [800, 600]

    expect(described_class.new(path: @path).window_size).to eq([800, 600])
  end

  it "coerces window_size= members to integers" do
    settings.window_size = ["800", "600"]

    expect(settings.window_size).to eq([800, 600])
  end

  it "falls back to the default when a stored window-size is not a pair" do
    File.write(@path, JSON.generate("window-size" => [1]))

    expect(described_class.new(path: @path).window_size).to eq([1024, 768])
  end

  describe "#apply_to" do
    it "sets the window's default size from the stored window-size" do
      window = double("window")
      expect(window).to receive(:set_default_size).with(1024, 768)

      settings.apply_to(window)
    end
  end

  describe "#remember" do
    it "records the window's default size when not maximized or fullscreened" do
      window = double("window", maximized?: false, fullscreened?: false, default_width: 640, default_height: 480)

      settings.remember(window)

      expect(settings.window_size).to eq([640, 480])
    end

    it "does not save while maximized, so the restored size survives" do
      window = double("window", maximized?: true, fullscreened?: false, default_width: 640, default_height: 480)

      settings.remember(window)

      expect(settings.window_size).to eq([1024, 768])
    end

    it "does not save while fullscreened" do
      window = double("window", maximized?: false, fullscreened?: true, default_width: 640, default_height: 480)

      settings.remember(window)

      expect(settings.window_size).to eq([1024, 768])
    end
  end

  describe "reading a corrupt file" do
    it "warns and falls back to the defaults rather than raising" do
      File.write(@path, "{not json")

      expect { described_class.new(path: @path) }.to output(/Error parsing/).to_stderr
      expect(described_class.new(path: @path).first_run?).to be(true)
    end
  end
end
