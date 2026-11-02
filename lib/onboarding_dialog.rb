# frozen_string_literal: true

require 'adwaita'

require_relative 'onboarding_dialog_page'

# OnboardingDialog is the first-run tour: five carousel pages with dots under
# them, back and next buttons either side, and a close button that reads
# "No Thanks" on the first page and "Close" on the last.
#
# Ported from upstream's src/onboarding-dialog.vala and
# src/ui/onboarding-dialog.ui, including the page titles and descriptions the
# .ui file carries.
#
class OnboardingDialog
  PAGES = [
    {
      title:       'Welcome to Connections',
      description: 'Click next to learn about remote desktop.',
      image:       'welcome.svg',
    },
    {
      title:       'Access other desktops',
      description: 'Connections allows viewing the screens of other desktops. ' \
                   'They can also be controlled using the pointer and keyboard.',
      image:       'remote-computer.svg',
    },
    {
      title:       'Connect to different operating systems',
      description: 'You can access Linux, Mac, and Windows desktops.',
      image:       'multiplatform.svg',
    },
    {
      title:       'Setup is required',
      description: 'Remote desktop typically needs to be enabled on the computer ' \
                   'you want to connect to.',
      image:       'configure-access.svg',
    },
    {
      title:       'Start by creating your first connection',
      description: 'To begin, you will need the address of the computer you want ' \
                   'to connect to.',
      image:       'thankyou.svg',
    },
  ].freeze

  # Upstream's art lives in its gresource bundle under
  # src/ui/onboarding/. This port ships no art, so a page only gets a
  # background image when one is found beside the sources.
  ART_DIRECTORY = File.expand_path('../data/onboarding', __dir__)

  def initialize(parent = nil)
    @parent = parent
    @pages = PAGES.map do |page|
      OnboardingDialogPage.new(
        title:       page[:title],
        description: page[:description],
        image:       art_path(page[:image]),
      )
    end
  end

  def build
    window.tap do |win|
      win.transient_for = @parent
      win.modal = true
      win.content = box

      box.tap do |b|
        b.append(overlay)
        b.append(button_box)

        overlay.tap do |ov|
          ov.child = carousel
          ov.add_overlay(indicator)

          @pages.each { |page| carousel.append(page.build) }
        end

        button_box.tap do |bb|
          bb.append(go_back_button)
          bb.append(close_button)
          bb.append(go_next_button)

          go_back_button.signal_connect('clicked') { on_back_button_clicked }
          go_next_button.signal_connect('clicked') { on_next_button_clicked }
          close_button.signal_connect('clicked') { win.close }
        end

        indicator.carousel = carousel
        carousel.signal_connect('notify::position') { on_position_changed }
      end

      key_controller.signal_connect('key-pressed') do |_controller, keyval, _code, _state|
        on_key_pressed(keyval)
      end
      win.add_controller(key_controller)

      on_position_changed
    end
  end

  def present = window.present

  # Upstream's on_next_button_clicked.
  def on_next_button_clicked
    (position + 1).then do |index|
      if index < @pages.length
        carousel.scroll_to(carousel.get_nth_page(index), true)
      end
    end
  end

  # Upstream's on_back_button_clicked.
  def on_back_button_clicked
    (position - 1).then do |index|
      if index >= 0
        carousel.scroll_to(carousel.get_nth_page(index), true)
      end
    end
  end

  # Upstream's on_position_changed: the back and next buttons disappear at the
  # ends of the carousel, and the close button only shows there.
  def on_position_changed
    position.then do |index|
      (index.zero?).then do |first|
        (index == @pages.length - 1).then do |last|
          go_back_button.visible = !first
          go_next_button.visible = !last
          close_button.visible = first || last
          if first
            close_button.label = '_No Thanks'
          else
            close_button.label = '_Close'
          end
        end
      end
    end
  end

  def on_key_pressed(keyval)
    (keyval == Gdk::Keyval::KEY_Escape).then do |escape|
      if escape
        window.close
        true
      else
        false
      end
    end
  end

  def window
    @window ||= Adwaita::Window.new.tap do |win|
      win.title = 'Welcome to Connections'
      win.set_default_size(700, 700)
    end
  end

  def box = @box ||= Gtk::Box.new(:vertical, 0)
  def overlay = @overlay ||= Gtk::Overlay.new

  def carousel
    @carousel ||= Adwaita::Carousel.new.tap do |c|
      c.vexpand = true
      c.hexpand = true
    end
  end

  def indicator
    @indicator ||= Adwaita::CarouselIndicatorDots.new.tap do |dots|
      dots.valign = :end
      dots.margin_bottom = 12
    end
  end

  def button_box
    @button_box ||= Gtk::Box.new(:horizontal, 12).tap do |b|
      b.halign = :center
      b.margin_top = 12
      b.margin_bottom = 24
      b.margin_start = 24
      b.margin_end = 24
    end
  end

  def go_back_button
    @go_back_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'go-previous-symbolic'
      button.valign = :center
      button.add_css_class('circular')
    end
  end

  def go_next_button
    @go_next_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'go-next-symbolic'
      button.valign = :center
      button.add_css_class('circular')
    end
  end

  def close_button
    @close_button ||= Gtk::Button.new(label: '_No Thanks').tap do |button|
      button.use_underline = true
      button.valign = :center
      button.add_css_class('pill')
    end
  end

  def key_controller = @key_controller ||= Gtk::EventControllerKey.new

  private

    # Upstream rounds the carousel position to the nearest page.
    def position = carousel.position.round

    def art_path(basename)
      File.join(ART_DIRECTORY, basename).then do |path|
        if File.exist?(path)
          path
        end
      end
    end
end
