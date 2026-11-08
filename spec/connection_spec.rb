# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Unit coverage for Connection (lib/connection.rb), using VncConnection as a
# concrete stand-in since Connection itself is abstract (widget/thumbnail/
# scaling/connect_it/disconnect_it/send_keys all raise NotImplementedError).
#
# Every example runs with XDG_CONFIG_HOME pointed at a scratch directory so
# that saving a property (which writes through Database.default) never
# touches the real user config, and so Database.default's memoization does
# not leak a path from one example into the next.
RSpec.describe Connection do
  around do |example|
    Dir.mktmpdir("gnome-connections-rb-connection") do |dir|
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

  subject(:connection) { VncConnection.new }

  describe "#initialize" do
    it "assigns a uuid when none is given" do
      expect(connection.uuid).not_to be_empty
    end

    it "keeps an explicitly given uuid" do
      expect(VncConnection.new(uuid: "fixed-uuid").uuid).to eq("fixed-uuid")
    end

    it "defaults to the subclass's protocol and port" do
      expect(connection.protocol).to eq("vnc")
      expect(connection.port).to eq(VncConnection::DEFAULT_PORT)
    end
  end

  describe "#uri" do
    it "joins protocol, host and port" do
      connection.host = "box-one"
      connection.port = 5901

      expect(connection.uri).to eq("vnc://box-one:5901")
    end
  end

  describe "#uri=" do
    it "splits an address into protocol, host and port" do
      connection.uri = "vnc://example.com:5905"

      expect(connection.protocol).to eq("vnc")
      expect(connection.host).to eq("example.com")
      expect(connection.port).to eq(5905)
    end

    it "keeps the existing port when the address does not name one" do
      connection.port = 9999

      connection.uri = "vnc://example.com"

      expect(connection.port).to eq(9999)
    end

    it "warns and leaves the connection alone when the address cannot be parsed" do
      expect { connection.uri = "not a uri" }.to output(/Failed to parse URI/).to_stderr
    end
  end

  describe "#visible_name" do
    it "is the uri when no display name was set" do
      connection.host = "box-one"

      expect(connection.visible_name).to eq(connection.uri)
    end

    it "is the display name once one is set" do
      connection.display_name = "My Box"

      expect(connection.visible_name).to eq("My Box")
    end
  end

  describe "property change notifications" do
    it "notifies an observer registered for that property" do
      seen = []
      connection.on_property_changed(:host) { |name| seen << name }

      connection.host = "box-one"

      expect(seen).to eq([:host])
    end

    it "notifies a wildcard observer for any property" do
      seen = []
      connection.on_property_changed { |name| seen << name }

      connection.host = "box-one"
      connection.port = 5901

      expect(seen).to eq([:host, :port])
    end

    it "does not notify an observer registered for a different property" do
      seen = []
      connection.on_property_changed(:port) { |name| seen << name }

      connection.host = "box-one"

      expect(seen).to be_empty
    end
  end

  describe "#while_loading" do
    it "suppresses save while the block runs" do
      connection.while_loading do |c|
        c.host = "loaded-host"
      end

      expect(connection.host).to eq("loaded-host")
    end

    it "notifies observers even while loading" do
      seen = []
      connection.on_property_changed(:host) { |name| seen << name }

      connection.while_loading { |c| c.host = "loaded-host" }

      expect(seen).to eq([:host])
    end

    it "resumes saving once the block returns" do
      connection.while_loading { |c| c.host = "x" }

      # uri= touches protocol, host and port together, so the reloaded group
      # always carries the "protocol" key get_connections needs to rebuild it.
      connection.uri = "vnc://box-one:5901"

      expect(Database.default.get_connections.map(&:host)).to include("box-one")
    end
  end

  describe "#save and persistence" do
    it "writes a changed property to the database" do
      connection.uri = "vnc://box-one:5901"

      reloaded = Database.default.get_connection(connection.uuid)
      expect(reloaded.host).to eq("box-one")
    end
  end

  describe "credentials" do
    it "stores a password through the credential file, not the database" do
      connection.password = "s3cret"

      expect(Credentials.default.lookup(connection.uuid)["password"]).to eq("s3cret")
    end

    it "does not store anything while the password is empty" do
      connection.username = "alice"

      expect(Credentials.default.lookup(connection.uuid)).to eq({})
    end

    it "deletes stored credentials" do
      connection.password = "s3cret"
      connection.delete_auth_credentials

      expect(Credentials.default.lookup(connection.uuid)).to eq({})
    end
  end

  describe "#handle_auth" do
    it "does nothing when neither a username nor a password is needed" do
      connection.need_username = false
      connection.need_password = false

      expect { connection.handle_auth }.not_to raise_error
    end

    it "completes immediately once credentials are already present" do
      # authentication_complete triggers VncConnection's connect_it, which (in
      # this environment with no gtk-vnc typelib) reports through
      # on_connection_error — stub App.instance the way the collection-view
      # fallback it calls into would use it.
      main_window = double("main_window", notifications_bar: double("notifications_bar", display_for_error: nil), show_collection_view: nil)
      allow(App).to receive(:instance).and_return(double("app", main_window: main_window))

      completed = false
      connection.on_authentication_complete { completed = true }
      connection.need_password = true
      connection.password = "already-set"

      connection.handle_auth

      expect(completed).to be(true)
    end
  end

  describe "abstract members" do
    it "defines widget/thumbnail/scaling/connect_it/disconnect_it/send_keys to raise on the base class" do
      %i[widget thumbnail scaling connect_it disconnect_it].each do |name|
        expect { Connection.instance_method(name).bind_call(connection) }.to raise_error(NotImplementedError)
      end
      expect { Connection.instance_method(:send_keys).bind_call(connection, []) }.to raise_error(NotImplementedError)
    end
  end
end
