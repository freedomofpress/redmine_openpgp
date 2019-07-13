#!/bin/env ruby
# encoding: utf-8

Redmine::Plugin.register :openpgp do
  name 'OpenPGP'
  author 'Alexander Blum'
  description 'Email encryption with the OpenPGP standard'
  version '1.0.1'
  author_url 'mailto:a.blum@free-reality.net'
  url 'https://github.com/C3S/redmine_openpgp'
  settings(:default => {
    'signature_needed' => false,
    'activation' => 'project',
    'unencrypted_mails' => 'filtered',
    'encrypted_html' => false,
    'filtered_mail_footer' => ''
  }, :partial => 'settings/openpgp')
  project_module :openpgp do
    permission :block_email, { :openpgp => :show }
  end
  menu :account_menu, :pgpkeys, { :controller => 'pgpkeys', :action => 'index' }, 
    :caption => 'PGP', :after => :my_account,
    :if => Proc.new { User.current.logged? }
end

Rails.configuration.to_prepare do
  # encrypt outgoing mails
  Mailer.send(:prepend, RedmineOpenpgp::EncryptMails)

  # decrypt received mails, handle them based on signature requirements
  MailHandler.send(:prepend, RedmineOpenpgp::DecryptMails)
end
