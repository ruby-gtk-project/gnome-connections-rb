# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Unit coverage for Credentials (lib/connection.rb), the file-backed stand-in
# for upstream's libsecret keyring entry (see that file's header comment for
# why there is no libsecret typelib to bind against here).
RSpec.describe Credentials do
  around do |example|
    Dir.mktmpdir("gnome-connections-rb-credentials") do |dir|
      @path = File.join(dir, "credentials.json")
      example.run
    end
  end

  subject(:credentials) { described_class.new(path: @path) }

  describe "#lookup" do
    it "returns an empty hash for a uuid that was never stored" do
      expect(credentials.lookup("missing")).to eq({})
    end

    it "returns an empty hash when the backing file does not exist yet" do
      expect(File.exist?(@path)).to be(false)
      expect(credentials.lookup("anything")).to eq({})
    end
  end

  describe "#store" do
    it "round-trips the fields it was given" do
      credentials.store("uuid-1", username: "alice", password: "s3cret", domain: nil)

      expect(credentials.lookup("uuid-1")).to eq(
        "username" => "alice",
        "password" => "s3cret",
      )
    end

    it "compacts nil fields instead of storing them" do
      credentials.store("uuid-1", username: nil, password: "s3cret", domain: nil)

      expect(credentials.lookup("uuid-1").keys).to eq(["password"])
    end

    it "creates the backing file mode 0600" do
      credentials.store("uuid-1", username: "alice", password: "p", domain: nil)

      mode = File.stat(@path).mode & 0o777
      expect(mode).to eq(0o600)
    end

    it "keeps other uuids' entries when storing a new one" do
      credentials.store("uuid-1", username: "alice", password: "p1", domain: nil)
      credentials.store("uuid-2", username: "bob", password: "p2", domain: nil)

      expect(credentials.lookup("uuid-1")["username"]).to eq("alice")
      expect(credentials.lookup("uuid-2")["username"]).to eq("bob")
    end
  end

  describe "#delete" do
    it "removes a stored entry" do
      credentials.store("uuid-1", username: "alice", password: "p", domain: nil)
      credentials.delete("uuid-1")

      expect(credentials.lookup("uuid-1")).to eq({})
    end

    it "does not raise when deleting a uuid that was never stored" do
      expect { credentials.delete("missing") }.not_to raise_error
    end
  end

  describe "#location" do
    it "reports the path it was constructed with" do
      expect(credentials.location).to eq(@path)
    end
  end

  describe "reading a corrupt file" do
    it "warns and treats it as empty rather than raising" do
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, "{not json")

      expect { credentials.lookup("uuid-1") }.to output(/Error parsing/).to_stderr
      expect(credentials.lookup("uuid-1")).to eq({})
    end
  end
end
