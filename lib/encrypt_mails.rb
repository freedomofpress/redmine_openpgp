module EncryptMails

  def self.included(base) # :nodoc:
    base.send(:include, InstanceMethods)
    base.class_eval do
      alias_method_chain :mail, :relocation
    end
  end

  module InstanceMethods

    # action names to be processed by this plugin
    def actions
      [
        'attachments_added',
        'document_added',
        'issue_add',
        'issue_edit',
        'lost_password',
        'message_posted',
        'news_added',
        'news_comment_added',
        'wiki_content_added',
        'wiki_content_updated'
      ]
    end

    # dispatched mail method
    def mail_with_relocation(headers={}, &block)

      # pass unchanged, if action does not match or plugin is inactive
      act = Setting.plugin_openpgp['activation']
      return mail_without_relocation(headers, &block) if
        act == 'none' or not actions.include? @_action_name or
        (act == 'project' and not project.try('module_enabled?', 'openpgp'))

      # relocate recipients
      if @_action_name == 'lost_password'
        recipients = password_reset_recipient(headers)
      else
        recipients = relocate_recipients(headers)
      end

      header = @_message.header.to_s

      # render and deliver encrypted mail
      reset(header)
      m = mail_without_relocation prepare_headers(
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
      m = mail_without_relocation prepare_headers(
        headers, recipients[:filtered], encrypt = false, sign = true
      ) do |format|
        format.text { render tpl }
        format.html { render tpl } unless Setting.plain_text_mail?
      end
      m.deliver

      # render unchanged mail (deliverd by calling method)
      reset(header)
      m = mail_without_relocation prepare_headers(
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

    # relocates reciepients (to, cc) of message
    def relocate_recipients(headers)

      # hash to be returned
      recipients = {
        :encrypted => {:to => [], :cc => []},
        :blocked   => {:to => [], :cc => []},
        :filtered  => {:to => [], :cc => []},
        :unchanged => {:to => [], :cc => []},
        :lost      => {:to => [], :cc => []}
      }

      # relocation of reciepients
      [:to, :cc].each do |field|
        headers[field].each do |user|

          # encrypted
          if Pgpkey.find_by(user_id: user.id).nil?
            logger.info "No public key found for #{user} <#{user.mail}> (#{user.id})" if logger
          else
            recipients[:encrypted][field].push user and next
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

    def find_key_by_email(email)

      user = User.find_by_mail(email)
      user_key = Pgpkey.find_by user_id: user.id
      unless user_key.nil?
        return user_key.fpr
      end

    end

    # handles headers for password reset emails, which have a single recipient
    def password_reset_recipient(headers)

      # hash to be returned
      recipient = {
        :encrypted => {:to => []},
        :blocked => {:to => []},
        :filtered  => {:to => []},
        :unchanged => {:to => []},
        :lost => {:to => []}
      }

      user = User.find_by_mail(headers[:to])
      user_key = Pgpkey.find_by(user_id: user.id)

      if user_key.nil?
        logger.info "No public key found for #{user} <#{user.mail}> (#{user.id})" if logger
      else
        recipient[:encrypted][:to].push user
      end

      # unencrypted
      case Setting.plugin_openpgp['unencrypted_mails']
        when 'blocked'
          recipient[:blocked][:to].push user
        when 'filtered'
          recipient[:filtered][:to].push user if user_key.nil?
        when 'unchanged'
          recipient[:unchanged][:to].push user if user_key.nil?
        else
          recipient[:lost][:to].push user
      end

      recipient

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
        if @_action_name == 'lost_password'
          h[:gpg][:keys][h[:to]] = find_key_by_email(headers[:to])
        else
        [:to, :cc].each do |field|
          h[field].each do |user|
            user_key = Pgpkey.find_by user_id: user.id
            unless user_key.nil?
              h[:gpg][:keys][user.mail] = user_key.fpr
            end
          end unless h[field].blank?
         end
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
