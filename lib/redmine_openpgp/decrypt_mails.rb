# frozen_string_literal: true

module RedmineOpenpgp
  module DecryptMails

    def dispatch_to_default
      project = target_project
      if @ignore_email and RedmineOpenpgp.active_on_project?(project)
        logger.info "MailHandler: invalid email rejected to project #{project}" if logger
      else
        super
      end
    end

    def receive(email, options={})
      # Extract useful metadata for logging
      sender_email = email.from.to_a.first.to_s.strip
      # Sometimes this isn't available after decryption. This seems like a bug,
      # so extract it here so we're guaranteed to have it
      message_id = email.message_id

      # We need to store this before decryption, because after decryption
      # email.encrypted? == false
      encrypted = email.encrypted?

      valid_signature = false
      signatures = []

      # encrypt and check validity of signature
      if encrypted
        email = email.decrypt(
          :password => Pgpkey.find_by(:user_id => 0),
          :verify => true
        )
        if valid_signature = email.signature_valid?
          signatures = email.signatures
        end
      elsif email.signed?
        verified = email.verify
        if valid_signature = verified.signature_valid?
          signatures = verified.signatures
        end
      end

      # compare identity of signature with sender
      if valid_signature and
          signatures.any? and
          sender_email.present? and
          user = User.having_mail(sender_email).first and
          key = Pgpkey.find_by(user_id: user.id)

        valid_signature = signatures.any? do |sig|
          key.subkeys.any? do |subkey|
            subkey.capability.include?(:sign) and subkey.fpr == sig.fpr
          end
        end
      else
        # only accept signatures that can be associated with a user
        valid_signature = false
      end


      # TODO right now, emails with broken signatures are treated like unsigned
      # mails. Do we want that?
      #
      # It might be better to ignore or flag tampered emails even when unsigned
      # emails are let in.
      #
      @ignore_email = !!(Setting.plugin_openpgp['signature_needed'] and not valid_signature)

      if logger
        logger.info "MailHandler: received email from #{sender_email} " +
          "with Message-ID #{message_id}: " +
          "encrypted=#{encrypted}, " +
          "valid=#{valid_signature}, "+
          "ignored=#{@ignore_email}"
      end

      super(email, options)
    end
  end
end
