# frozen_string_literal: true

# Config for development dependencies of this library
# i.e., not configured by this library
#
# SimpleCov & related config (must run BEFORE any other requires)
# NOTE: Gemfiles for non-coverage appraisals may not have kettle-soup-cover.
#       The rescue LoadError handles that scenario.
begin
  require "kettle-soup-cover"
  if Kettle::Soup::Cover::DO_COV
    # Requiring simplecov loads the project-local `.simplecov`.
    require "simplecov"
    require "kettle/soup/cover/config"
    SimpleCov.start
  end
rescue LoadError => error
  # check the error message and re-raise when unexpected
  raise error unless error.message.include?("kettle")
end

# External RSpec & related config
begin
  require "kettle/test/rspec"
  # `kettle/test/rspec` installs harness helpers documented in spec/README.md.
rescue LoadError => error
  # kettle-test is a declared development dependency (see the gemspec), but
  # is not always resolvable in every environment this suite runs in (for
  # example, a Nix dev shell whose gem set was pinned before kettle-test was
  # added). Degrade instead of aborting the whole run with a LoadError: the
  # suite falls back to plain RSpec with none of kettle-test's extra harness
  # helpers, rather than refusing to run at all.
  raise error unless error.message.include?("kettle")

  warn "spec_helper: kettle/test/rspec unavailable (#{error.message}); " \
       "running without its harness helpers."
end

# This library. The gem is named "gnome-connections-rb" (so its gemspec's
# version file lives at the conventional lib/gnome/connections/rb/version.rb
# path), but the application's own entry point is lib/gnome_connections.rb —
# see that file's comment for why.
require "gnome_connections"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
