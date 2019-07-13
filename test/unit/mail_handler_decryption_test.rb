require File.expand_path('../../test_helper', __FILE__)

class MailHandlerDecryptionTest < ActiveSupport::TestCase
  include PgpTestHelper
  include Redmine::I18n
  include Rails::Dom::Testing::Assertions
  fixtures :projects, :enabled_modules, :issues, :users,
           :email_addresses, :user_preferences, :members,
           :member_roles, :roles, :tokens, :journals,
           :journal_details, :trackers, :projects_trackers,
           :issue_statuses, :enumerations, :versions

  FIXTURES_PATH = File.dirname(__FILE__) + '/../../../../test/fixtures/mail_handler'
  SERVER_TO = "redmine@example.net"

  setup do
    (@mails = Mail::TestMailer.deliveries).clear
    ActionMailer::Base.deliveries.clear
    Setting.notified_events = Redmine::Notifiable.all.collect(&:name)
    User.current = nil
    Pgpkey.import user_id: 0, key: read_key("pgp.server.private.asc")
    @user = User.find_by_login 'jsmith'
  end

  teardown do
    Setting.clear_cache
    delete_keys
  end

  test "should add unsigned issue if not active" do
    k = generate_key email: @user.mail, password: 'abc'
    Pgpkey.create user_id: @user.id, fpr: k.fingerprint

    with_plugin_settings("signature_needed" => true, "activation" => "none") do
      assert_difference ->{Issue.count} do
        submit_email( 'ticket_on_given_project.eml', { :issue => {:tracker => 'Support request'} })
      end
    end

    with_plugin_settings("signature_needed" => true, "activation" => "project") do
      assert_difference ->{Issue.count} do
        submit_email( 'ticket_on_given_project.eml', { :issue => {:tracker => 'Support request'} })
      end
    end
  end


  test "should not add unsigned issue if active" do
    k = generate_key email: @user.mail, password: 'abc'
    Pgpkey.create user_id: @user.id, fpr: k.fingerprint

    with_plugin_settings("signature_needed" => true, "activation" => "all") do
      assert_no_difference ->{Issue.count} do
        submit_email( 'ticket_on_given_project.eml', { :issue => {:tracker => 'Support request'} })
      end
    end

    with_plugin_settings("signature_needed" => true, "activation" => "project") do
      Project.find('onlinestore').enabled_modules.create! name: 'openpgp'
      assert_no_difference ->{Issue.count} do
        submit_email( 'ticket_on_given_project.eml', { :issue => {:tracker => 'Support request'} })
      end
    end
  end

  test "should not add issue from invalid signed mail when sigs are required" do
    k = generate_key email: @user.mail, password: 'abc'
    Pgpkey.create user_id: @user.id, fpr: k.fingerprint

    with_plugin_settings("signature_needed"=>true, "activation" => "all") do
      assert_no_difference ->{Issue.count} do
        submit_signed_email(
          'ticket_on_given_project.eml',
          options: { password: 'abc' },
          mh_options: { :issue => {:tracker => 'Support request'} }
        ) do |mail|
          # modify the already signed content
          mail.text_part.body.raw_source.sub!(/Resolved/, 'Closed')
        end
      end
    end
  end

  test "should not add issue from invalid signed mail even when unsigned mails are OK" do
    skip "possible enhancement - never accept invalid signed mails"
    k = generate_key email: @user.mail, password: 'abc'
    Pgpkey.create user_id: @user.id, fpr: k.fingerprint

    with_plugin_settings("signature_needed"=>false, "activation" => "all") do
      assert_no_difference ->{Issue.count} do
        submit_signed_email(
          'ticket_on_given_project.eml',
          options: { password: 'abc' },
          mh_options: { :issue => {:tracker => 'Support request'} }
        ) do |mail|
          # modify the already signed content
          mail.text_part.body.raw_source.sub!(/Resolved/, 'Closed')
        end
      end
    end
  end

  test "should add issue from signed mail" do
    k = generate_key email: @user.mail, password: 'abc'
    Pgpkey.create user_id: @user.id, fpr: k.fingerprint

    with_plugin_settings("signature_needed" => true, "activation" => "all") do
      issue = nil
      assert_difference ->{Issue.count} do
        issue = submit_signed_email(
                  'ticket_on_given_project.eml',
                  options: { password: 'abc' },
                  mh_options: { :issue => {:tracker => 'Support request'} }
                )
      end
      assert issue.is_a?(Issue)
      assert !issue.new_record?
      issue.reload
      assert_equal 'Support request', issue.tracker.name
      assert_equal @user, issue.author
    end
  end

  test "should add issue from signed / encrypted mail" do
    k = generate_key email: @user.mail, password: 'abc'
    Pgpkey.create user_id: @user.id, fpr: k.fingerprint

    with_plugin_settings("signature_needed" => true, "activation" => "all") do
      issue = nil
      assert_difference ->{Issue.count} do
        issue = submit_encrypted_email(
                  'ticket_on_given_project.eml',
                  options: { password: 'abc', sign: true },
                  mh_options: { :issue => {:tracker => 'Support request'} }
                )
      end
      assert issue.is_a?(Issue)
      assert !issue.new_record?
      issue.reload
      assert_equal 'Support request', issue.tracker.name
      assert_equal @user, issue.author
    end
  end


  test "should not add issue from unsigned encrypted mail" do
    with_plugin_settings("signature_needed" => true, "activation" => "all") do
      assert_no_difference ->{Issue.count} do
        submit_encrypted_email(
          'ticket_on_given_project.eml',
          mh_options: { :issue => {:tracker => 'Support request'} }
        )
      end
    end
  end

  test "should add issue from encrypted mail" do
    with_plugin_settings("signature_needed" => false, "activation" => "all") do
      # This email contains: 'Project: onlinestore'
      issue = submit_encrypted_email(
                'ticket_on_given_project.eml',
                mh_options: { :issue => {:tracker => 'Support request'} }
              )
      assert issue.is_a?(Issue)
      assert !issue.new_record?
      issue.reload
      assert_equal 'Support request', issue.tracker.name
      assert_equal @user, issue.author
    end
  end


  private

  def submit_signed_email(filename, options: {}, mh_options: {})
    mail = sign_email filename, options
    if block_given?
      yield mail
    end
    MailHandler.receive(mail.to_s, mh_options)
  end

  def sign_email(filename, options)
    mail = Mail.new IO.read File.join FIXTURES_PATH, filename
    Mail::Gpg.sign mail, options.merge(sign: true)
  end

  def submit_encrypted_email(filename, options: {}, mh_options: {})
    mail = encrypt_email filename, options
    MailHandler.receive(mail.to_s, mh_options)
  end

  def encrypt_email(filename, options)
    mail = Mail.new IO.read File.join FIXTURES_PATH, filename
    mail.to = SERVER_TO
    Mail::Gpg.encrypt mail, options
  end

  def submit_email(filename, options={})
    raw = IO.read(File.join(FIXTURES_PATH, filename))
    yield raw if block_given?
    MailHandler.receive(raw, options)
  end

end
