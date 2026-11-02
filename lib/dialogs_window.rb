# frozen_string_literal: true

require 'adwaita'

# DialogsWindow is the single dialog a connection raises before it can be
# opened: certificate verification, certificate-change verification, or an
# authentication prompt.
#
# Ported from upstream's src/dialogs.vala and src/ui/dialog.ui. The three pages
# live in one stack, the header bar swaps between a Verify and a Connect
# button, and each page reports its answer through the block it was shown
# with.
#
# Upstream raises each page by setting a flag and polling it from a 50ms
# timeout, because the protocol backends call in from their own threads. The
# protocol backends here are not threaded, so each `show_*` presents its page
# directly.
#
class DialogsWindow
  def initialize
    @change_verification = false
    @certificate_verify_func = nil
    @certificate_change_verify_func = nil
    @authentication_func = nil
    @connection_name = ''
    @certificate_fingerprint = ''
  end

  def build(transient_for: nil)
    window.tap do |win|
      win.transient_for = transient_for
      win.modal = true
      win.content = toolbar_view

      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.content = content_stack
      end

      header_bar.title_widget = header_stack

      header_stack.tap do |s|
        s.add_named(verify_button, 'verify-button-page')
        s.add_named(connect_button, 'connect-button-page')
      end

      content_stack.tap do |s|
        s.add_named(certificate_page, 'certificate-verification')
        s.add_named(certificate_change_page, 'certificate-change-verification')
        s.add_named(authentication_page, 'authentication')
      end

      verify_button.signal_connect('clicked') { verify_button_clicked }
      connect_button.signal_connect('clicked') { connect_button_clicked }
      cancel_button.signal_connect('clicked') { cancel_connection }

      delete_local_certificate_switch.signal_connect('notify::active') do
        connect_button.sensitive = delete_local_certificate_switch.active?
      end

      authenticate_button.signal_connect('clicked') { authenticate_button_clicked }
      cancel_authentication_button.signal_connect('clicked') { cancel_authentication_clicked }

      [username_row, password_row, domain_row].each do |row|
        row.signal_connect('entry-activated') { authenticate_button_clicked }
      end

      key_controller.signal_connect('key-pressed') do |_controller, keyval, _code, _state|
        on_key_pressed(keyval)
      end
      win.add_controller(key_controller)

      win.signal_connect('close-request') do
        cancel_connection
        true
      end
    end
  end

  # Upstream's split_fingerprint: a 32-byte fingerprint is laid out as four
  # rows of eight, split into two groups of four.
  def split_fingerprint(fingerprint)
    fingerprint.split(':').then do |parts|
      if parts.length == 32
        (0...4).map do |row|
          [
            parts[(row * 8), 4].join(':'),
            parts[(row * 8) + 4, 4].join(':'),
          ].join('   ')
        end.join("\n").upcase
      else
        ''
      end
    end
  end

  # Upstream's show_certificate_verification.
  def show_certificate_verification(name, fingerprint, &block)
    @change_verification = false
    @connection_name = name
    @certificate_fingerprint = fingerprint
    @certificate_verify_func = block

    text_label.label = 'Connecting to “%s” for the first time. To be sure you\'re connecting ' \
                       'to the machine it claims to be, please verify the fingerprints match. ' \
                       'This process is only done once.' % name
    fingerprint_value.label = split_fingerprint(fingerprint)

    content_stack.visible_child_name = 'certificate-verification'
    header_stack.visible_child_name = 'verify-button-page'
    header_bar.visible = true
    window.present
  end

  # Upstream's show_certificate_change_verification.
  def show_certificate_change_verification(name, fingerprint, &block)
    @change_verification = true
    @connection_name = name
    @certificate_fingerprint = fingerprint
    @certificate_change_verify_func = block

    certificate_change_text_label.label =
      'The remote server “%s” certificate doesn\'t match local copy. It may be ' \
      'someone\'s pretending to be the server.' % name
    fingerprint_value.label = split_fingerprint(fingerprint)

    content_stack.visible_child_name = 'certificate-change-verification'
    header_stack.visible_child_name = 'connect-button-page'
    header_bar.visible = true
    window.present
  end

  # Upstream's show_authentication: only the rows the connection asked for are
  # shown, and the first of them takes the focus.
  def show_authentication(name, need_username:, need_password:, need_domain:, &block)
    @connection_name = name
    @authentication_func = block

    username_row.visible = need_username
    password_row.visible = need_password
    domain_row.visible = need_domain

    authentication_text.label =
      'The remote server “%s” requires the following authentication details to ' \
      'continue to connect:' % name

    content_stack.visible_child_name = 'authentication'
    header_bar.visible = false
    window.present

    focus_first_row(need_username, need_password, need_domain)
  end

  # Upstream's cancel_connection: whichever verification is on screen is
  # answered with a no.
  def cancel_connection
    if @change_verification
      @certificate_change_verify_func&.call(false)
    else
      @certificate_verify_func&.call(false)
    end

    dismiss
  end

  # Upstream's verify_button_clicked_cb.
  def verify_button_clicked
    if @change_verification
      @certificate_change_verify_func&.call(true)
    else
      @certificate_verify_func&.call(true)
    end

    dismiss
  end

  # Upstream's connect_button_clicked_cb: accepting the changed certificate
  # moves on to verifying the new one.
  def connect_button_clicked
    show_certificate_verification(
      @connection_name,
      @certificate_fingerprint,
      &@certificate_verify_func
    )
  end

  # Upstream's authenticate_button_clicked.
  def authenticate_button_clicked
    window.visible = false

    @authentication_func.then do |func|
      if func
        @authentication_func = nil
        func.call(username_row.text, password_row.text, domain_row.text)
      end
    end

    dismiss
  end

  # Upstream's cancel_authentication_clicked, which answers with empty
  # credentials.
  def cancel_authentication_clicked
    window.visible = false

    @authentication_func.then do |func|
      if func
        @authentication_func = nil
        func.call('', '', '')
      end
    end

    dismiss
  end

  def on_key_pressed(keyval)
    (keyval == Gdk::Keyval::KEY_Escape).then do |escape|
      if escape
        cancel_connection
        true
      else
        false
      end
    end
  end

  # Upstream's dismiss: hide and clear, so the next prompt starts empty.
  def dismiss
    window.visible = false
    username_row.text = ''
    password_row.text = ''
    domain_row.text = ''
    delete_local_certificate_switch.active = false
  end

  def window
    @window ||= Adwaita::Window.new.tap do |win|
      # Translators: The dialog with this title is shown to the user before
      # opening the connection if needed (e.g. certificate confirmation).
      win.title = 'Open Connection'
      win.set_default_size(480, 360)
      win.hide_on_close = true
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

  def header_bar
    @header_bar ||= Adwaita::HeaderBar.new.tap do |bar|
      bar.show_end_title_buttons = false
      bar.pack_start(cancel_button)
    end
  end

  def header_stack = @header_stack ||= Gtk::Stack.new
  def content_stack = @content_stack ||= Gtk::Stack.new

  def cancel_button = @cancel_button ||= Gtk::Button.new(label: 'Cancel')

  def verify_button
    @verify_button ||= Gtk::Button.new(label: 'Verify').tap do |button|
      button.add_css_class('suggested-action')
    end
  end

  def connect_button
    @connect_button ||= Gtk::Button.new(label: 'Connect').tap do |button|
      button.sensitive = false
      button.add_css_class('destructive-action')
    end
  end

  # Page one: verify the fingerprint of a certificate seen for the first time.
  def certificate_page
    @certificate_page ||= Gtk::Box.new(:vertical, 12).tap do |page|
      page.margin_top = 24
      page.margin_bottom = 24
      page.margin_start = 24
      page.margin_end = 24
      page.append(certificate_title)
      page.append(text_label)
      page.append(fingerprint_value)
    end
  end

  def certificate_title
    @certificate_title ||= Gtk::Label.new('Verify Fingerprint').tap do |label|
      label.add_css_class('title-2')
    end
  end

  def text_label
    @text_label ||= Gtk::Label.new.tap do |label|
      label.wrap = true
      label.max_width_chars = 50
      label.justify = :center
    end
  end

  def fingerprint_value
    @fingerprint_value ||= Gtk::Label.new.tap do |label|
      label.selectable = true
      label.add_css_class('monospace')
    end
  end

  # Page two: the certificate changed since the last connection.
  def certificate_change_page
    @certificate_change_page ||= Gtk::Box.new(:vertical, 12).tap do |page|
      page.margin_top = 24
      page.margin_bottom = 24
      page.margin_start = 24
      page.margin_end = 24
      page.append(certificate_change_title)
      page.append(certificate_change_text_label)
      page.append(delete_local_certificate_group)
    end
  end

  def certificate_change_title
    @certificate_change_title ||= Gtk::Label.new('Unexpected Certificate').tap do |label|
      label.add_css_class('title-2')
    end
  end

  def certificate_change_text_label
    @certificate_change_text_label ||= Gtk::Label.new.tap do |label|
      label.wrap = true
      label.max_width_chars = 50
      label.justify = :center
    end
  end

  def delete_local_certificate_group
    @delete_local_certificate_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.add(delete_local_certificate_row)
    end
  end

  def delete_local_certificate_row
    @delete_local_certificate_row ||= Adwaita::ActionRow.new.tap do |row|
      row.title = 'Delete Local Certificate'
      row.add_suffix(delete_local_certificate_switch)
      row.activatable_widget = delete_local_certificate_switch
    end
  end

  def delete_local_certificate_switch
    @delete_local_certificate_switch ||= Gtk::Switch.new.tap do |switch|
      switch.valign = :center
    end
  end

  # Page three: username, password and domain.
  def authentication_page
    @authentication_page ||= Gtk::Box.new(:vertical, 12).tap do |page|
      page.margin_top = 24
      page.margin_bottom = 24
      page.margin_start = 24
      page.margin_end = 24
      page.append(authentication_title)
      page.append(authentication_text)
      page.append(authentication_group)
      page.append(authentication_buttons)
    end
  end

  def authentication_title
    @authentication_title ||= Gtk::Label.new('Authentication Required').tap do |label|
      label.add_css_class('title-2')
    end
  end

  def authentication_text
    @authentication_text ||= Gtk::Label.new.tap do |label|
      label.wrap = true
      label.max_width_chars = 50
      label.justify = :center
    end
  end

  def authentication_group
    @authentication_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.add(username_row)
      group.add(password_row)
      group.add(domain_row)
    end
  end

  def username_row
    @username_row ||= Adwaita::EntryRow.new.tap do |row|
      row.title = 'Username…'
    end
  end

  # Upstream pairs a plain entry with a reveal button and an icon it swaps by
  # hand; an Adwaita password row carries exactly that control already, so the
  # row is the port of all three widgets.
  def password_row
    @password_row ||= Adwaita::PasswordEntryRow.new.tap do |row|
      row.title = 'Password…'
    end
  end

  def domain_row
    @domain_row ||= Adwaita::EntryRow.new.tap do |row|
      row.title = 'Domain…'
      row.add_suffix(help_domain_button)
    end
  end

  def help_domain_button
    @help_domain_button ||= Gtk::MenuButton.new.tap do |button|
      button.icon_name = 'help-about-symbolic'
      button.valign = :center
      button.add_css_class('flat')
      button.popover = domain_help_popover
    end
  end

  def domain_help_popover
    @domain_help_popover ||= Gtk::Popover.new.tap do |popover|
      popover.child = Gtk::Label.new(
        "Domain field is commonly optional and can be\nleft empty.",
      ).tap do |label|
        label.margin_top = 12
        label.margin_bottom = 12
        label.margin_start = 12
        label.margin_end = 12
      end
    end
  end

  def authentication_buttons
    @authentication_buttons ||= Gtk::Box.new(:horizontal, 12).tap do |box|
      box.homogeneous = true
      box.append(cancel_authentication_button)
      box.append(authenticate_button)
    end
  end

  def cancel_authentication_button
    @cancel_authentication_button ||= Gtk::Button.new(label: 'Cancel').tap do |button|
      button.name = 'cancel_button'
    end
  end

  def authenticate_button
    @authenticate_button ||= Gtk::Button.new(label: 'Authenticate').tap do |button|
      button.name = 'authenticate_button'
      button.add_css_class('suggested-action')
    end
  end

  def key_controller = @key_controller ||= Gtk::EventControllerKey.new

  private

    def focus_first_row(need_username, need_password, need_domain)
      if need_username
        username_row.grab_focus
      elsif need_password
        password_row.grab_focus
      elsif need_domain
        domain_row.grab_focus
      end
    end
end
