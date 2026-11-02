# frozen_string_literal: true

require 'adwaita'

# ShortcutsDialog lists the keyboard shortcuts.
#
# Ported from upstream's src/ui/kbd-shortcuts-window.ui, which is a
# GtkShortcutsWindow with an Overview section and a Connection Display
# section. The items and accelerators below are the same ones, and they are
# the five the window actually binds.
#
class ShortcutsDialog < Adwaita::ShortcutsDialog
  SECTIONS = {
    'Overview'           => [
      ['Help', 'F1'],
      ['Search', '<Ctrl>f'],
      ['Keyboard Shortcuts', '<Ctrl>question'],
      ['Quit', '<Ctrl>q'],
    ],
    'Connection Display' => [
      ['Fullscreen', 'F11'],
    ],
  }.freeze

  def initialize
    super()
    self.title = 'Keyboard Shortcuts'
  end

  def build
    tap do |dialog|
      SECTIONS.each do |title, items|
        dialog.add(section(title, items))
      end
    end
  end

  private

    def section(title, items)
      Adwaita::ShortcutsSection.new.tap do |section|
        section.title = title
        items.each { |label, accelerator| section.add(item(label, accelerator)) }
      end
    end

    # Positional, not keyword, arguments — even though the error a no-argument
    # new raises advertises the signatures as "title: utf8, accelerator: utf8".
    def item(label, accelerator) = Adwaita::ShortcutsItem.new(label, accelerator)
end
