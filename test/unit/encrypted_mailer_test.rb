require File.expand_path('../../test_helper', __FILE__)

class EncryptedMailerTest < ActiveSupport::TestCase
  include PgpTestHelper
  include Redmine::I18n
  include Rails::Dom::Testing::Assertions
  fixtures :projects, :enabled_modules, :issues, :users, :email_addresses, :user_preferences, :members,
           :member_roles, :roles, :documents, :attachments, :news,
           :tokens, :journals, :journal_details, :changesets,
           :trackers, :projects_trackers,
           :issue_statuses, :enumerations, :messages, :boards, :repositories,
           :wikis, :wiki_pages, :wiki_contents, :wiki_content_versions,
           :versions,
           :comments

  setup do
    ActionMailer::Base.deliveries.clear
    Setting.plain_text_mail = '0'
    Setting.default_language = 'en'
    User.current = nil
    Pgpkey.import user_id: 0, key: read_key("pgp.server.private.asc")
  end

  teardown do
    delete_keys
  end

  test "should preserve HTML part" do
    user1 = User.generate!
    k = generate_key email: user1.mail, password: 'abc'
    Pgpkey.create user_id: user1.id, fpr: k.fingerprint

    with_settings(plugin_openpgp: {"signature_needed"=>false, "encryption_scope"=>"project", "unencrypted_mails"=>"filtered", "encrypted_html"=>true, "filtered_mail_footer"=>"" }) do

      news = News.find(1)
      news.project.enabled_module('news').add_watcher(user1)
      Mailer.deliver_news_added(news)
      assert m = decrypt_email(to: user1.mail, password: 'abc')
      assert m.multipart?
      assert_equal 2, m.parts.size
      assert_mail_body_match "eCookbook first release", m
      assert_select_email do
        assert_select 'h1', text: "eCookbook first release"
      end
    end
  end


  test "should encrypt news_added notification" do
    user1 = User.generate!
    k = generate_key email: user1.mail, password: 'abc'
    Pgpkey.create user_id: user1.id, fpr: k.fingerprint

    user2 = User.generate!
    k = generate_key email: user2.mail, password: 'def'
    Pgpkey.create user_id: user2.id, fpr: k.fingerprint

    news = News.find(1)
    news.project.enabled_module('news').add_watcher(user1)
    Mailer.deliver_news_added(news)

    assert_include user1.mail, recipients
    assert_not_include user2.mail, recipients

    assert m = decrypt_email(to: user1.mail, password: 'abc')
    assert_include "eCookbook first release", m.decoded
  end

  test "should encrypt security notification" do
    skip "not yet implemented"
    user = User.find 1
    Pgpkey.import user_id: 1, key: @pub_key
    set_language_if_valid user.language

    with_settings emails_footer: "footer without link" do
      sender = User.find(2)
      sender.remote_ip = '192.168.1.1'
      assert Mailer.deliver_security_notification(user, sender, message: :notice_account_password_updated)

      assert mail = decrypt_email(to: user.mail)
      assert_mail_body_match sender.login, mail
      assert_mail_body_match '192.168.1.1', mail
      assert_mail_body_match I18n.t(:notice_account_password_updated), mail
    end
  end

  private

  def decrypt_email(to:, password: nil)
    mail = ActionMailer::Base.deliveries.detect{|m|Array(m.bcc).include? to}
    assert mail.present?, "no mail for #{to} found"
    encrypted = mail.parts.detect{|p| p.content_type =~ /encrypted\.asc/}
    assert encrypted.present?, "found email to #{to} but it's not encrypted"
    assert clear = GPGME::Crypto.new.decrypt(encrypted.body.to_s, password: password)
    Mail.new clear
  end

  def read_key(name)
    IO.read Rails.root.join("plugins", "openpgp", "test", name)
  end

  # Returns an array of email addresses to which emails were sent
  def recipients
    ActionMailer::Base.deliveries.map(&:bcc).flatten.sort
  end

  def last_email
    mail = ActionMailer::Base.deliveries.last
    assert_not_nil mail
    mail
  end

  def text_part
    last_email.parts.detect {|part| part.content_type.include?('text/plain')}
  end

  def html_part
    last_email.parts.detect {|part| part.content_type.include?('text/html')}
  end
end
