require File.expand_path('../../test_helper', __FILE__)

class PgpkeysAdministrationTest < Redmine::IntegrationTest
  include PgpTestHelper

  fixtures :users, :email_addresses, :user_preferences

  setup do
    @priv_key = read_key "pgp.server.private.asc"
    @pub_key = read_key "pgp.user.public.asc"
    @passphrase_key = read_key "pgp.passphrase.private.asc"
    @priv_key_fpr = "4DBBD6E21C39DBD75DFC5FFFBC84D5A85E4D733E"
  end

  # TODO: use standard require_login before action
  test "should redirect anonymous to login page" do
    skip "future enhancement"
    get "/pgp"
    assert_redirected_to "/login"

    post "/pgp"
    assert_redirected_to "/login"
  end

  test "should handle missing key arg" do
    skip "future enhancement"
    log_user "admin", "admin"
    post "/pgp/create", params: { }
    assert_response :success
  end

  test "should check server key passphrase" do
    assert Pgpkey.where(user_id: 0).none?
    log_user "admin", "admin"
    get "/pgp"
    assert_response :success

    assert_no_difference ->{ Pgpkey.count } do
      post "/pgp/create", params: { key: @passphrase_key, user_id: "0", secret: "wrong" }
    end
    assert_redirected_to "/pgp"
  end

  test "admin should be able to set server key" do
    assert Pgpkey.where(user_id: 0).none?
    log_user "admin", "admin"
    get "/pgp"
    assert_response :success

    assert_difference ->{ Pgpkey.where(user_id: 0).count } do
      post "/pgp/create", params: { key: @priv_key, user_id: "0" }
    end
    assert_redirected_to "/pgp"

    assert k = Pgpkey.where(user_id: 0).first
    assert_equal @priv_key_fpr, k.fpr
    assert k.secret.blank?
  end

  test "non-admin should not be able to set server key" do
    assert Pgpkey.where(user_id: 0).none?
    log_user "jsmith", "jsmith"
    get "/pgp"
    assert_response :success

    assert_no_difference ->{ Pgpkey.count } do
      post "/pgp/create", params: { key: @priv_key, user_id: "0" }
    end
    assert_redirected_to "/pgp"
  end

  test "user should be able to set own public key" do
    assert Pgpkey.none?

    log_user "jsmith", "jsmith"
    get "/pgp"
    assert_response :success

    assert_difference ->{ Pgpkey.where(user_id: 2).count } do
      post "/pgp/create", params: { key: @pub_key, user_id: 2 }
    end
    assert_redirected_to "/pgp"
  end

  test "user should not be able to set other users public key" do
    assert Pgpkey.none?
    log_user "jsmith", "jsmith"
    get "/pgp"
    assert_response :success

    assert_no_difference ->{ Pgpkey.count } do
      post "/pgp/create", params: { key: @pub_key, user_id: 3 }
    end
    assert_redirected_to "/pgp"
  end


end
