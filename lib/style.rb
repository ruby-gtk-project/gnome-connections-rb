# frozen_string_literal: true

require 'adwaita'

# Style carries the application stylesheet.
#
# Ported from upstream's src/ui/style.css, which upstream loads from its
# gresource bundle in the Window constructor. This port has no gresource
# bundle, so the same rules live here as a string and are installed on the
# default display.
#
# The colour names are the GTK4/Libadwaita ones: upstream's @theme_bg_color,
# @theme_fg_color and @borders are the GTK3 names, and under Libadwaita the
# equivalents are @window_bg_color, @window_fg_color and @borders.
#
module Style
  CSS = <<~CSS
    /* Screenshot flash */
    @keyframes flash_animation {
        50% {
            opacity: 0.2;
        }
    }

    .flash {
        border: 1px solid transparent;
        animation: flash_animation;
        animation-duration: 300ms;
        animation-iteration-count: 1;
    }

    .thumbnail {
        background: @window_bg_color;
        color: @window_fg_color;
        border: 1px solid @borders;
    }

    /* Onboarding dialog */
    .onboarding-dialog-page {
        background-repeat: no-repeat;
        background-size: 60%;
        background-position: center 15%;
    }
  CSS

  # Upstream's dialogs.vala loads these two rules of its own, so the
  # authentication dialog's buttons sit flush in the dialog's bottom edge.
  DIALOG_CSS = <<~CSS
    button#authenticate_button {
        border-radius: 0px;
        border-bottom: 0px;
        border-right: 0px;
    }

    button#cancel_button {
        border-radius: 0px;
        border-bottom: 0px;
        border-left: 0px;
        border-right: 0px;
    }
  CSS

  # Installing the same CSS twice would stack two providers on the display, so
  # the first install wins and later calls are no-ops.
  def self.install(display = Gdk::Display.default)
    @installed ||= {}
    display.then do |target|
      if target && !@installed[target.object_id]
        @installed[target.object_id] = true
        add_provider(target, "#{CSS}\n#{DIALOG_CSS}")
      end
    end
  end

  # A page's background art is per-page, so each onboarding page installs its
  # own provider on its own style context rather than on the whole display.
  def self.provider_for(css)
    Gtk::CssProvider.new.tap { |provider| provider.load_from_data(css) }
  end

  def self.add_provider(display, css)
    Gtk::StyleContext.add_provider_for_display(
      display,
      provider_for(css),
      Gtk::StyleProvider::PRIORITY_APPLICATION,
    )
  end
end
