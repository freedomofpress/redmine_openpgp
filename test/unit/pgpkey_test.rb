require File.expand_path('../../test_helper', __FILE__)

class PgpkeyTest < ActiveSupport::TestCase
  include PgpTestHelper

  setup do
    @priv_key = read_key "pgp.server.private.asc"
    @pub_key = read_key "pgp.user.public.asc"
    @passphrase_key = read_key "pgp.passphrase.private.asc"
  end

  test "should import public key" do
    assert key = Pgpkey.import(user_id: 1, key: @pub_key)
    assert_equal "BE49710891B0D87485423EB7005D8C98C055666A", key.fpr
    assert_equal 1, key.user_id
    assert key.secret.blank?
    assert key.persisted?
  end

  test "should import private key" do
    assert key = Pgpkey.import(user_id: 0, key: @priv_key)
    assert_equal "4DBBD6E21C39DBD75DFC5FFFBC84D5A85E4D733E", key.fpr
    assert_equal 0, key.user_id
    assert key.secret.blank?
    assert key.persisted?
  end

  test "import should check passphrase" do
    assert_raise(GPGME::Error::BadPassphrase) do
      assert_no_difference ->{ Pgpkey.count } do
        Pgpkey.import(user_id: 0, key: @passphrase_key, secret: "wrong")
      end
    end
  end

end
