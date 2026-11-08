# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Unit coverage for Database (lib/database.rb), the GKeyFile-backed
# connection store.
#
# Connection#save always writes through Database.default (see connection.rb),
# not through whatever Database instance happens to be at hand, so exercising
# Database#add_connection — which builds a connection and saves it — means
# isolating Database.default itself behind a scratch XDG_CONFIG_HOME, the
# same way the real application only ever has one.
RSpec.describe Database do
  around do |example|
    Dir.mktmpdir("gnome-connections-rb-database") do |dir|
      original_xdg = ENV["XDG_CONFIG_HOME"]
      ENV["XDG_CONFIG_HOME"] = dir
      Database.instance_variable_set(:@default, nil)
      Credentials.instance_variable_set(:@default, nil)
      example.run
      ENV["XDG_CONFIG_HOME"] = original_xdg
      Database.instance_variable_set(:@default, nil)
      Credentials.instance_variable_set(:@default, nil)
    end
  end

  subject(:database) { described_class.default }

  describe ".protocols" do
    it "maps vnc and rdp to their connection classes" do
      expect(described_class.protocols).to include(
        "vnc" => VncConnection,
        "rdp" => RdpConnection,
      )
    end

    it "omits spice, since SpiceConnection.available? is false here" do
      expect(described_class.protocols).not_to have_key("spice")
    end
  end

  describe "#location" do
    it "defaults under XDG_CONFIG_HOME" do
      expect(database.location).to eq(File.join(ENV.fetch("XDG_CONFIG_HOME"), Database::FILENAME))
    end

    it "honours an explicit path" do
      custom = File.join(Dir.mktmpdir("gnome-connections-rb-database-custom"), "other.db")
      expect(described_class.new(path: custom).location).to eq(custom)
    end
  end

  describe "#get_connections" do
    it "is empty for a database that does not exist yet" do
      expect(File.exist?(database.location)).to be(false)
      expect(database.get_connections).to eq([])
    end

    it "creates the file mode 0600 on first access" do
      database.get_connections

      mode = File.stat(database.location).mode & 0o777
      expect(mode).to eq(0o600)
    end
  end

  describe "#add_connection" do
    it "builds a VncConnection from a vnc:// uri and saves it" do
      connection = database.add_connection("vnc://box-one:5901")

      expect(connection).to be_a(VncConnection)
      expect(connection.host).to eq("box-one")
      expect(database.get_connections.map(&:uuid)).to include(connection.uuid)
    end

    it "builds an RdpConnection from an rdp:// uri" do
      connection = database.add_connection("rdp://box-two")

      expect(connection).to be_a(RdpConnection)
      expect(connection.host).to eq("box-two")
    end

    it "warns and adds nothing for an unknown scheme" do
      expect { database.add_connection("ftp://box") }.to output(/unknown protocol/).to_stderr
      expect(database.get_connections).to eq([])
    end
  end

  describe "#get_connection" do
    it "rebuilds a connection from its stored properties" do
      added = database.add_connection("vnc://box-one:5901")

      fresh = database.get_connection(added.uuid)

      expect(fresh).to be_a(VncConnection)
      expect(fresh.host).to eq("box-one")
      expect(fresh.port).to eq(5901)
    end

    it "returns nil for a uuid that is not in the database" do
      expect(database.get_connection("missing")).to be_nil
    end
  end

  describe "#find_connection_by_uri" do
    it "finds an existing connection by protocol, host and port" do
      added = database.add_connection("vnc://box-one:5901")

      found = database.find_connection_by_uri("vnc://box-one:5901")

      expect(found.uuid).to eq(added.uuid)
    end

    it "matches on protocol and host alone when the uri names no port" do
      added = database.add_connection("vnc://box-one:5901")

      found = database.find_connection_by_uri("vnc://box-one")

      expect(found.uuid).to eq(added.uuid)
    end

    it "returns nil when nothing matches" do
      database.add_connection("vnc://box-one:5901")

      expect(database.find_connection_by_uri("vnc://box-two")).to be_nil
    end

    it "warns and returns nil for an unparseable uri" do
      expect { database.find_connection_by_uri("not a uri") }.to output(/Failed to parse URI/).to_stderr
      expect(database.find_connection_by_uri("not a uri")).to be_nil
    end
  end

  describe "#delete_connection" do
    it "removes the connection's group from the database" do
      added = database.add_connection("vnc://box-one:5901")

      database.delete_connection(added)

      expect(database.get_connections).to eq([])
    end
  end

  describe "#save_property" do
    it "round-trips a boolean property" do
      added = database.add_connection("vnc://box-one:5901")
      added.view_only = true

      reloaded = database.get_connection(added.uuid)

      expect(reloaded.view_only).to be(true)
    end

    it "round-trips an integer property" do
      added = database.add_connection("vnc://box-one:5901")
      added.port = 5950

      reloaded = database.get_connection(added.uuid)

      expect(reloaded.port).to eq(5950)
    end
  end
end
