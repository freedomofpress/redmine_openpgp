class Pgpkey < ActiveRecord::Base
  unloadable

  def public_key
    GPGME::Key.get(self.fpr).export(:armor => true).to_s
  end

  def metadata
    GPGME::Key.get(self.fpr).to_s
  end

  def subkeys
    GPGME::Key.get(self.fpr).subkeys
  end

  def self.import(user_id: , key: , secret: nil)
    gpgme_import = GPGME::Key.import(key)
    if import = gpgme_import.imports[0] and
      fpr = import.fpr and
      key = GPGME::Key.get(fpr) and
      fpr == key.fingerprint

      if user_id == 0
        begin
          gpgme = GPGME::Crypto.new
          enc = gpgme.encrypt('test', recipients: fpr, always_trust: true).to_s
          dec = gpgme.decrypt(enc, password: secret).to_s
          unless "test" == dec
            fail "bad encryption result (should be >test<): >#{dec}<"
          end
        rescue
          key.delete!(true)
          raise $!
        end
      end

      create user_id: user_id, fpr: fpr, secret: secret
    end
  end
end
