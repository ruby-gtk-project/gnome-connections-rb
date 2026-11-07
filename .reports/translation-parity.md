# Translation parity — gnome-connections-rb vs. origin/master

(Upstream's current default branch is `origin/master`; `origin/main` does not
exist in this clone. `origin/master` is the GTK3+libhandy spec version used
throughout this audit round, consistent with `.reports/component-inventory.md`.)

## Upstream

- `git ls-tree -r --name-only origin/master | grep '^po/'` → 59 files:
  `LINGUAS`, `POTFILES.in`, `meson.build`, and **55 `.po` files**, one per
  shipped locale (`po/LINGUAS` lists 55 language codes, including variants
  like `sr@latin.po`).
- Sampled `po/de.po`: **97 `msgid` entries.**
- `po/POTFILES.in` lists 25 source files whose strings are extracted:
  7 `src/*.vala` files, 10 `src/ui/*.ui` files, and 3 `data/*.in`/`.xml`
  files (desktop entry, metainfo, D-Bus service description).
- Strings are marked via Vala's `_()` and `N_()` and the GtkBuilder
  `translatable="yes"` attribute in `.ui` files.
- `help/` additionally carries 29 translated locale `.po` files for the user
  documentation. This report counts the 55 app-UI `.po` files as the
  headline figure because that is what `po/LINGUAS` and `po/POTFILES.in`
  track, but the 29 `help/` files are upstream work too, equally unported
  (there is no `help/` tree in this port at all), and are not being written
  off here — they are additional, uncounted debt on top of the figures
  below.

## Port

- `grep -rln 'gettext\|FastGettext\|_(' lib/ exe/` → **zero matches.**
- `find . -iname '*.po' -o -iname LINGUAS' -not -path './.git/*'` → **zero
  matches.** No `po/` directory exists anywhere in the port.
- `Gemfile` / `gnome-connections-rb.gemspec` → no `gettext`, `fast_gettext`,
  or any i18n gem is a dependency.
- Every user-visible string identified in `.reports/component-inventory.md`
  (menu items, dialog titles, button labels, the onboarding carousel copy,
  the "Authentication Required" / "Unexpected Certificate" dialog text, the
  shortcuts window labels, error strings like "Too many command-line
  arguments specified.") is a bare Ruby string literal in `lib/*.rb`. None is
  wrapped in any translation marker.

## What this means against the skill's three claims

1. **Key sets equal?** No. Upstream: 97 msgids sampled from one locale file
   (the true `.pot` count is at least that, likely somewhat higher once
   duplicates across files are deduplicated). Port: **0.**
2. **Byte-identical keys?** Vacuously fails — there is no catalogue extracted
   from the port to compare against upstream's.
3. **Languages ship?** No. 55 upstream `.po` files for the app UI (84 total
   counting `help/`), 0 carried over, 0 `.mo` compiled, 0 installed, and no
   mechanism in the port (`Gemfile`, `lib/`) that could even consume one if
   it existed. A user running the system in German, French, Korean, or any
   of the other 54 shipped languages sees English text, unconditionally.

## Verdict

**Total gap**, identical in kind and scale to the finding already on record
for the pilot port (`gnome-contacts-rb/.reports/translation-parity.md`): 0 of
the upstream catalogue survives. Nothing is marked, nothing is extracted,
nothing ships. `.reports/component-inventory.md` for this port does not even
flag this as deferred — i18n is absent from its notes entirely, so it is
reported here as the headline finding of this audit, not a rough edge.
