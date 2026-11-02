# frozen_string_literal: true

require 'adwaita'

require_relative 'style'

# OnboardingDialogPage is one page of the first-run carousel: a title, a
# description, and a piece of background art behind them.
#
# Ported from upstream's src/onboarding-dialog-page.vala and
# src/ui/onboarding-dialog-page.ui. Upstream loads the art from its gresource
# bundle with a CSS rule installed on the page's own style context when the
# page is mapped; this port takes a file path instead, because it ships no
# gresource bundle, and a page given no art simply has none.
#
class OnboardingDialogPage
  attr_reader :title, :description, :image

  def initialize(title:, description:, image: nil)
    @title = title
    @description = description
    @image = image
  end

  def build
    box.tap do |b|
      b.append(title_label)
      b.append(description_label)

      title_label.label = @title
      description_label.label = @description

      b.signal_connect('map') { load_css }
    end
  end

  # Upstream's load_css: the art is a background image on the page itself.
  def load_css
    @image.then do |path|
      if path && File.exist?(path)
        box.style_context.add_provider(
          Style.provider_for(
            ".onboarding-dialog-page {\n  background-image: url(\"file://#{path}\");\n}\n",
          ),
          Gtk::StyleProvider::PRIORITY_APPLICATION,
        )
      end
    end
  end

  def box
    @box ||= Gtk::Box.new(:vertical, 10).tap do |b|
      b.vexpand = true
      b.hexpand = true
      b.valign = :start
      b.add_css_class('onboarding-dialog-page')
    end
  end

  def title_label
    @title_label ||= Gtk::Label.new.tap do |label|
      label.margin_top = 330
      label.wrap = true
      label.justify = :center
      label.add_css_class('onboarding-dialog-page-title-label')
      label.add_css_class('title-1')
    end
  end

  def description_label
    @description_label ||= Gtk::Label.new.tap do |label|
      label.wrap = true
      label.max_width_chars = 60
      label.justify = :center
      label.halign = :center
      label.use_markup = true
    end
  end
end
