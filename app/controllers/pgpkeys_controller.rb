class PgpkeysController < ApplicationController

  def index
    @server_pgpkey = Pgpkey.find_by user_id: 0
    @user_pgpkey = Pgpkey.find_by user_id: User.current.id
  end

  def create
    redirect_to :action => 'index'

    # params conversions
    @key = params['key']
    @user_id = params['user_id'].to_i
    @secret = params['secret']

    # sanity checks FIXME move these to some kind of form object
    flash[:error] = l(:flash_key_exists) and return if key_exists?
    flash[:error] = (@user_id == 0 ? l(:flash_private_key_not_valid) : l(:flash_public_key_not_valid)) and
      return if not key_valid?
    flash[:error] = l(:flash_update_not_allowed) and return if not update_allowed?
    flash[:warning] = l(:flash_no_secret) if @user_id == 0 and @secret == ''

    key = nil
    begin
      unless key = Pgpkey.import(user_id: @user_id, key: @key, secret: @secret)

        flash[:error] = l(:flash_import_error)
        return
      end
    rescue GPGME::Error::BadPassphrase
      flash.delete(:warning)
      flash[:error] = l(:flash_bad_passphrase)
      return
    end

    if key.persisted?
      @fpr = key.fpr
      flash[:notice] = l(:flash_create_successful)
    else
      flash[:error] = l(:flash_unknown_error)
    end
  end

  def delete
    redirect_to :action => 'index'

    # params conversions
    @user_id = params['user_id'].to_i

    # sanity checks
    flash[:error] = l(:flash_key_not_exists) and return if not key_exists?
    flash[:error] = l(:flash_update_not_allowed) and return if not update_allowed?

    # remove key from db
    key = Pgpkey.find_by user_id: @user_id
    fpr = key.fpr
    if key.delete
      flash[:notice] = l(:flash_delete_successful)
    else
      flash[:error] = l(:flash_unknown_error)
    end

    # remove key from gpg key ring, if no other reference exists
    if not Pgpkey.find_by fpr: fpr
      gpgme_key = GPGME::Key.get(fpr)
      gpgme_key.delete!(true)
    end
  end

  def generate
    redirect_to :action => 'index'
    @user_id = 0

    # sanity checks
    flash[:error] = l(:flash_key_exists) and return if key_exists?
    flash[:error] = l(:flash_update_not_allowed) and return if not update_allowed?
    flash[:warning] = l(:flash_no_secret) if @user_id == 0 and @secret == ''

    # prepare gpg parameter
    data = "<GnupgKeyParms format=\"internal\">\n"
    data += "Key-Type: "       +params['key_type']      +"\n"
    data += "Key-Length: "     +params['key_length']    +"\n"
    data += "Subkey-Type: "    +params['subkey_type']   +"\n"
    data += "Subkey-Length: "  +params['subkey_length'] +"\n"
    data += "Name-Real: "      +params['name_real']     +"\n"
    data += "Name-Comment: "   +params['name_comment']  +"\n" unless params['name_comment'].blank?
    data += "Name-Email: "     +params['name_email']    +"\n"
    data += "Expire-Date: "    +params['expire_date']   +"\n"
    data += "Passphrase: "     +params['passphrase']    +"\n" unless params['passphrase'].blank?
    data += "</GnupgKeyParms>"

    # create key and save into gpg key ring
    GPGME::Ctx.new.genkey(data)

    # save generated key into db
    key = GPGME::Key.find(nil, params['name_email']).first
    if Pgpkey.create(:user_id => 0, :fpr => key.fingerprint, :secret => params['passphrase'])
      flash[:notice] = l(:flash_generate_successful)
    else
      flash[:error] = l(:flash_unknown_error)
    end
  end

  def key_exists?
    Pgpkey.find_by user_id: @user_id
  end

  def key_valid?
    if @user_id == 0
      regex = /^\A\s*-----BEGIN PGP PRIVATE KEY BLOCK-----.*-----END PGP PRIVATE KEY BLOCK-----\s*?\z/m
    else
      regex = /^\A\s*-----BEGIN PGP PUBLIC KEY BLOCK-----.*-----END PGP PUBLIC KEY BLOCK-----\s*?\z/m
    end
    @key.match(regex)
  end

  def update_allowed?
    return true if User.current.admin
    return true if User.current.id == @user_id
  end
end
