class GmailConnection < ApplicationRecord
  belongs_to :user

  enum :sync_status, { disconnected: 0, active: 1, syncing: 2, error: 3 }

  validates :email, presence: true, uniqueness: { scope: :user_id }

  def self.encryption_key
    ENV["JWT_SECRET"].presence || Rails.application.secret_key_base
  end

  # Encrypt refresh token before saving
  def encrypted_refresh_token=(value)
    if value.present?
      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.encrypt
      key = OpenSSL::Digest::SHA256.digest(self.class.encryption_key)
      cipher.key = key
      iv = cipher.random_iv
      encrypted = cipher.update(value) + cipher.final
      write_attribute(:encrypted_refresh_token, Base64.encode64(iv + encrypted))
    end
  end

  # Decrypt refresh token
  def refresh_token
    if encrypted_refresh_token.present?
      data = Base64.decode64(encrypted_refresh_token)
      iv = data[0..15]
      encrypted = data[16..-1]

      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.decrypt
      key = OpenSSL::Digest::SHA256.digest(self.class.encryption_key)
      cipher.key = key
      cipher.iv = iv

      cipher.update(encrypted) + cipher.final
    end
  end

  # Check if token is expired
  def token_expired?
    token_expires_at.blank? || token_expires_at <= Time.current
  end

  # Check if connection is active
  def active?
    sync_status == "active" && !token_expired?
  end

  # Update sync status
  def mark_as_synced!
    update(sync_status: :active, last_sync_at: Time.current)
  end

  # Mark as disconnected
  def mark_as_disconnected!
    update(sync_status: :disconnected)
  end
end
