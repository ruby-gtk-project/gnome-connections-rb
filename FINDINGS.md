# Findings — gnome-connections-rb

A standing decision record for gaps that are not fixable by writing more
Ruby in this repository, so future rounds do not have to re-derive them from
scratch (per this fleet's accountability-ensurance skill's instruction that a
calmly-worded file-header paragraph is not a substitute for a logged
decision).

## 1. No protocol (VNC, RDP, SPICE) can render a remote desktop — environment ceiling, confirmed again this round

**Status: open, not fixable from this repository. Decision: (b) — recorded
here rather than left as three file-header paragraphs.**

Upstream's whole purpose is remote-desktop display. `lib/vnc_connection.rb`,
`lib/rdp_connection.rb` and `lib/spice_connection.rb` port every piece of
upstream behaviour around the display widget (properties, persistence,
`.vnc`-file import, scale modes, the certificate/authentication signal
plumbing that a real backend would raise), but the display widget itself —
`Vnc.Display`, `FrdpDisplay`, `Spice.Display` — has no port, because none of
`gtk-vnc`, `gtk-frdp`, `spice-gtk` ship a GObject-Introspection `.typelib` in
this fleet's dev environment.

Re-confirmed this round, not assumed from the prior audit's wording:

```
find /nix/store -iname "*vnc*.typelib" -o -iname "*frdp*.typelib" -o -iname "*spice*.typelib"
```

returns nothing. (A plain substring search on `/nix/store` turns up many
paths containing "vnc" as a hash-collision substring — e.g.
`0bg6vnc1j8ppj5z8nfmh32b923mqqqbm-fuzzy-...` — none of which are gtk-vnc or
any `.typelib` file; this was checked explicitly to make sure "no typelib
found" was not a false negative from a search that matched too narrowly.)

Every `connect_it` on all three connection classes therefore reports through
`on_connection_error`, the same fallback path upstream itself takes when a
server refuses a connection — this is the honest behaviour for a build with
no working backend, not a stub standing in for unwritten code.

**Why this is not something the port team can code around:** there is no
pure-Ruby VNC/RDP/SPICE client to swap in that would satisfy "a connection
protocol can render a remote desktop" — the point of using `gtk-vnc` etc. is
that they are the GTK-native, GObject-Introspectable widgets upstream itself
uses; reimplementing RFB/RDP/SPICE wire protocols and a software renderer in
Ruby would not be a *port* of `gnome-connections` any more, and is out of
scope for what this task is (porting the application upstream wrote, not
writing a new remote-desktop client upstream never had).

**The two honest paths forward, neither of which this round's work can take
on its own:**

- (a) Get a working `gtk-vnc`, `gtk-frdp`, or `spice-gtk` typelib into the
  fleet's Nix environment (adding the right `nixpkgs` package — or, if
  nixpkgs genuinely lacks an introspectable build of any of the three,
  packaging one) so that at least one protocol can be exercised for real.
  This is an environment/infrastructure change outside `lib/`, `exe/`, and
  `test/` — it belongs in the fleet's Nix flake/devshell definition, not in
  a Ruby source file.
- (b) If (a) is permanently infeasible (e.g. none of the three libraries
  have ever shipped introspection data upstream, in any distro), that should
  be said explicitly by whoever owns the fleet's environment — this file is
  that explicit statement for this port, and it should be revisited, not
  silently inherited, each time this repository is next worked.

## 2. `kettle-test` is unresolvable offline — degraded gracefully, not supplied

`spec/spec_helper.rb`'s `rescue LoadError` around `require "kettle/test/rspec"`
(fixed in `ec3297b`) means the suite no longer crashes, but it does not mean
`kettle-test`'s harness helpers (`stub_env`, `hide_env`, `pending_for`, etc.,
documented in `spec/README.md`) are available — they still are not, in this
offline Nix dev shell. The specs added this round (`spec/*_spec.rb`) do not
use any of them; they are written against plain RSpec (`double`,
`Dir.mktmpdir`, `ENV`), which is resolvable offline via the dev shell's own
`rspec-core`/`rspec-mocks` gems. If `kettle-test` becomes resolvable in a
future environment, the existing specs do not need to change — they simply
gain the option of using the extra helpers, they do not depend on their
absence.

`bundle exec rspec` still fails with a bundler gem-resolution error in this
shell (re-checked this round); the dev shell's own `ruby -e
'require "rspec/core"; ...'` invocation (see `TEST_PARITY.md`) is the one
that works, and is what this round used to verify all 61 new examples pass.

## 3. n/a items confirmed still out of scope

`connections.gresource.xml` (a build-generated resource manifest, not a
source file), `po/` (translations — out of scope per this fleet's
translation-parity skill), the dead `src/ui/auth-notification.ui` template
(unreferenced by any `.vala` file upstream), and the orphan
`fingerprint2-symbolic.svg` icon remain correctly excluded from the 24-unit
list in `PORTING.md`. Nothing new was found this round that changes that.
