# frozen_string_literal: true

module RedmineOpenpgp
  module EncryptMails

    # action names to be processed by this plugin
    ENCRYPT_ACTIONS = %w(
      attachments_added
      document_added
      issue_add
      issue_edit
      lost_password
      message_posted
      news_added
      news_comment_added
      security_notification
      settings_updated
      wiki_content_added
      wiki_content_updated
    )

    GLOBAL_ACTIONS = %w(
      lost_password
      security_notification
      settings_updated
    )

    # dispatched mail method
    def mail(headers={}, &block)

      # no project defined during the lost_password action, so we need to handle
      # special case when act == 'project' instead of 'all'
      active = RedmineOpenpgp.active_on_project?(
        project, global: GLOBAL_ACTIONS.include?(@_action_name)
      )

      unless active and ENCRYPT_ACTIONS.include?(@_action_name)
        return super
      end

      # email headers for password resets contain a single recipient e-mail address instead of an array of users
      # so we need to rewrite them to work with the relocate_recipients function
      if @_action_name == 'lost_password'
        headers = password_reset_headers(headers)
      end

      # relocate recipients
      recipients = relocate_recipients(headers)
      header = @_message.header.to_s

      # render and deliver encrypted mail
      reset(header)
      m = super prepare_headers(
        headers, recipients[:encrypted], encrypt = true, sign = true
      ) do |format|
        format.text
        format.html if not Setting.plain_text_mail? and
          Setting.plugin_openpgp['encrypted_html']
      end
      m.deliver

      # render and deliver filtered mail
      reset(header)
      tpl = @_action_name + '.filtered'
      m = super prepare_headers(
        headers, recipients[:filtered], encrypt = false, sign = true
      ) do |format|
        format.text { render tpl }
        format.html { render tpl } unless Setting.plain_text_mail?
      end
      m.deliver

      # render unchanged mail (deliverd by calling method)
      reset(header)
      m = super prepare_headers(
        headers, recipients[:unchanged], encrypt = false, sign = false
      ) do |format|
        format.text
        format.html unless Setting.plain_text_mail?
      end

      m

    end

    # get project dependent on action and object
    def project

      case @_action_name
      when 'attachments_added'
        @attachments.first.project
      when 'document_added'
        @document.project
      when 'issue_add', 'issue_edit'
        @issue.project
      when 'message_posted'
        @message.project
      when 'news_added', 'news_comment_added'
        @news.project
      when 'wiki_content_added', 'wiki_content_updated'
        @wiki_content.project
      else
        nil
      end

    end

    # loads a user object by e-mail (necessary for password reset emails
    # if we want to be able to look up their PGP key)
    def password_reset_headers(headers)

      headers[:to] = [User.find_by_mail(headers[:to])]
      headers

    end

    # relocates recipients (to, cc) of message
    def relocate_recipients(headers)

      # hash to be returned
      recipients = {
        :encrypted => {:to => [], :cc => []},
        :blocked   => {:to => [], :cc => []},
        :filtered  => {:to => [], :cc => []},
        :unchanged => {:to => [], :cc => []},
        :lost      => {:to => [], :cc => []}
      }

      # relocation of recipients
      [:to, :cc].each do |field|
        Array(headers[field]).each do |user|

          # Try to catch case where an email was passed where the address isn't a current user
          begin
            # encrypted
            if Pgpkey.find_by(user_id: user.id).nil?
              logger.info "No public key found for #{user} <#{user.mail}> (#{user.id})" if logger
            else
              recipients[:encrypted][field].push user and next
            end
          rescue NoMethodError
            logger.info "Tried to encrypt non-system user #{user}"
          end

          # unencrypted
          case Setting.plugin_openpgp['unencrypted_mails']
          when 'blocked'
            recipients[:blocked][field].push user
          when 'filtered'
            recipients[:filtered][field].push user
          when 'unchanged'
            recipients[:unchanged][field].push user
          else
            recipients[:lost][field].push user
          end

        end unless headers[field].blank?
      end

      recipients

    end

    # resets the mail for sending mails multiple times
    def reset(header)

      @_mail_was_called = false
      @_message = Mail.new
      @_message.header header

    end

    # prepares the headers for different configurations
    def prepare_headers(headers, recipients, encrypt, sign)

      h = headers.deep_dup

      # headers for recipients
      h[:to] = recipients[:to]
      h[:cc] = recipients[:cc]

      # headers for gpg
      h[:gpg] = {
        encrypt: false,
        sign: false
      }

      # headers for encryption
      if encrypt
        h[:gpg][:encrypt] = true
        # add pgp keys for emails
        h[:gpg][:keys] = {}
        [:to, :cc].each do |field|
          h[field].each do |user|
            user_key = Pgpkey.find_by user_id: user.id
            unless user_key.nil?
              h[:gpg][:keys][user.mail] = user_key.fpr
            end
          end unless h[field].blank?
        end
      end

      # headers for signature
      if sign
        server_key = Pgpkey.find_by(:user_id => 0)
        unless server_key.nil?
          h[:gpg][:sign] = true
          h[:gpg][:sign_as] = Setting['mail_from']
          h[:gpg][:password] = server_key.secret
        end
      end

      h

    end

  end
end
