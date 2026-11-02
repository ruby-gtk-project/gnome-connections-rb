# frozen_string_literal: true

require 'adwaita'
require 'uri'

require_relative 'spice_connection'

# Assistant is the new-connection popover: an address entry, a radio button
# per protocol, a Help button and a Connect button.
#
# Ported from upstream's src/assistant.vala and src/ui/assistant.ui. Typing an
# address with a scheme selects the matching protocol; typing one without a
# scheme gets the selected protocol's scheme prefixed when it is submitted.
# The SPICE radio button is only shown when the build can speak SPICE, as
# upstream's Config.HAS_SPICE does.
#
class Assistant
  SUPPORTED_SCHEMES = %w[rdp vnc spice].freeze

  def build
    popover.tap do |p|
      p.child = box

      box.tap do |b|
        b.append(address_box)
        b.append(protocol_box)
        b.append(button_box)

        address_box.tap do |ab|
          ab.append(address_label)
          ab.append(url_entry)

          url_entry.tap do |entry|
            entry.signal_connect('changed') { on_url_entry_changed }
            entry.signal_connect('activate') { on_url_entry_activated }
          end
        end

        protocol_box.tap do |pb|
          pb.append(protocol_label)
          pb.append(rdp_radio_button)
          pb.append(vnc_radio_button)
          pb.append(spice_radio_button)

          [rdp_radio_button, vnc_radio_button, spice_radio_button].each do |radio|
            radio.signal_connect('toggled') { on_url_entry_changed }
          end

          spice_radio_button.visible = SpiceConnection.available?
        end

        button_box.tap do |bb|
          bb.append(help_button)
          bb.append(create_button)

          help_button.signal_connect('clicked') { on_help_button_clicked }
          create_button.signal_connect('clicked') { on_create_connection_button_clicked }
        end
      end
    end
  end

  def popdown = popover.popdown
  def popup = popover.popup

  def popover
    @popover ||= Gtk::Popover.new.tap do |p|
      p.has_arrow = true
    end
  end

  def box = @box ||= Gtk::Box.new(:vertical, 0)

  def address_box
    @address_box ||= Gtk::Box.new(:vertical, 5).tap do |b|
      b.margin_top = 10
      b.margin_bottom = 10
      b.margin_start = 10
      b.margin_end = 10
    end
  end

  def address_label
    @address_label ||= Gtk::Label.new(
      'Enter the network identifier of the remote desktop to connect to:',
    ).tap do |label|
      label.halign = :start
      label.xalign = 0
      label.wrap = true
      label.max_width_chars = 40
    end
  end

  def url_entry
    @url_entry ||= Gtk::Entry.new.tap do |entry|
      entry.hexpand = true
    end
  end

  def protocol_box
    @protocol_box ||= Gtk::Box.new(:vertical, 5).tap do |b|
      b.margin_top = 10
      b.margin_bottom = 10
      b.margin_start = 10
      b.margin_end = 10
    end
  end

  def protocol_label
    @protocol_label ||= Gtk::Label.new('Connection Type').tap do |label|
      label.halign = :start
      label.add_css_class('heading')
    end
  end

  def rdp_radio_button
    @rdp_radio_button ||= Gtk::CheckButton.new('RDP (Standard, high performance)').tap do |radio|
      radio.active = true
    end
  end

  def vnc_radio_button
    @vnc_radio_button ||= Gtk::CheckButton.new('VNC (Legacy)').tap do |radio|
      radio.group = rdp_radio_button
    end
  end

  def spice_radio_button
    @spice_radio_button ||= Gtk::CheckButton.new('SPICE (Virtual machines)').tap do |radio|
      radio.group = rdp_radio_button
    end
  end

  def button_box
    @button_box ||= Gtk::Box.new(:horizontal, 5).tap do |b|
      b.margin_top = 10
      b.margin_bottom = 10
      b.margin_start = 10
      b.margin_end = 10
    end
  end

  def help_button
    @help_button ||= Gtk::Button.new(label: 'Help').tap do |button|
      button.hexpand = true
      button.halign = :start
    end
  end

  def create_button
    @create_button ||= Gtk::Button.new(label: 'Connect').tap do |button|
      button.sensitive = false
      button.halign = :end
      button.add_css_class('suggested-action')
    end
  end

  # Upstream's uri_has_supported_scheme.
  def uri_has_supported_scheme?(uri)
    SUPPORTED_SCHEMES.any? { |scheme| uri.start_with?("#{scheme}://") }
  end

  # Upstream's on_url_entry_changed: keep the radio buttons in step with
  # whatever scheme the address names, and only enable Connect for an address
  # that actually has a host.
  def on_url_entry_changed
    url_entry.text.empty?.then do |blank|
      if blank
        create_button.sensitive = false
      else
        update_for_address(prefixed_address(url_entry.text))
      end
    end
  end

  # Upstream's on_create_connection_button_clicked.
  def on_create_connection_button_clicked
    App.instance.add_connection(prefixed_address(url_entry.text))
    url_entry.text = ''
    popdown
  end

  # Upstream's on_url_entry_activated.
  def on_url_entry_activated
    create_button.sensitive.then do |ready|
      if ready
        create_button.activate
      end
    end
  end

  def on_help_button_clicked
    App.instance.open_uri("#{App::HELP_URI}/connect")
  end

  private

    # Upstream prefixes the address with the selected protocol when the address
    # does not name one itself.
    def prefixed_address(address)
      uri_has_supported_scheme?(address).then do |explicit|
        if explicit
          address
        else
          "#{selected_scheme}://#{address}"
        end
      end
    end

    def selected_scheme
      if rdp_radio_button.active?
        'rdp'
      elsif spice_radio_button.active?
        'spice'
      else
        'vnc'
      end
    end

    # Setting the radio buttons re-emits "toggled", which lands back here;
    # upstream's handler has the same shape and relies on the second pass
    # settling. The flag stops the pass happening at all.
    def update_for_address(address)
      @updating.then do |reentered|
        unless reentered
          @updating = true
          apply_address(address)
          @updating = false
        end
      end
    end

    def apply_address(address)
      parse(address).then do |uri|
        if uri
          rdp_radio_button.active = uri.scheme == 'rdp'
          vnc_radio_button.active = uri.scheme == 'vnc'
          spice_radio_button.active = uri.scheme == 'spice'
          create_button.sensitive = !uri.host.to_s.empty?
        else
          create_button.sensitive = false
        end
      end
    end

    def parse(address)
      URI.parse(address)
    rescue URI::InvalidURIError
      nil
    end
end
