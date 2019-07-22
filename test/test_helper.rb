# Load the Redmine helper
require File.expand_path(File.dirname(__FILE__) + '/../../../test/test_helper')

ActiveSupport::TestCase.class_eval do
  def with_plugin_settings(settings = {})
    with_settings(plugin_openpgp: {
      'activation' => 'all',
      'signature_needed' => false,
      'unencrypted_mails' => 'filtered',
      'encrypted_html' => false,
      'filtered_mail_footer' => '',
    }.merge(settings)) do
      yield
    end
  end
end

module PgpTestHelper

  def read_key(name)
    IO.read Rails.root.join("plugins", "openpgp", "test", name)
  end

  def delete_keys
    @keys.each{|k| k.delete!(true) rescue nil} if @keys
  end

  def generate_key(email: , password: nil, name: email)
    @keys ||= []
    unless k = GPGME::Key.find(:secret, email).first
      GPGME::Ctx.new do |gpg|
        gpg.generate_key <<-END
          <GnupgKeyParms format="internal">
            Key-Type: DSA
            Key-Length: 1024
            Subkey-Type: ELG-E
            Subkey-Length: 1024
            Name-Real: #{email}
            Name-Email: #{email}
            Expire-Date: 0
            Passphrase: #{password}
          </GnupgKeyParms>
        END
      end
      k = GPGME::Key.find(:secret, email).first
    end
    if k
      @keys << k
      k
    end
  end

end
