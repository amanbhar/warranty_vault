class User < ApplicationRecord
  has_secure_password

  enum :role, { member: 0, premium: 1, admin: 2 }

  has_many :invoices, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :invoice_items, through: :invoices
  has_many :item_warranties, through: :invoice_items
  has_many :user_reminder_preferences, dependent: :destroy
  has_one :gmail_connection, dependent: :destroy

  has_one_attached :avatar

  validates :email, presence: true, uniqueness: { case_sensitive: false },
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, if: :password_required?

  before_save :downcase_email
  after_create :initialize_default_reminder_preferences

  def initialize_default_reminder_preferences
    user_reminder_preferences.create!(days_before_expiry: 30, reminder_type: :default)
  end

  # Email verification methods

  # Check if user can login (email must be verified)
  def can_login?
    email_verified?
  end

  # Generate verification token and send email
  def send_verification_email
    EmailService.send_verification_email(self)
  end

  # Verify email with token
  def verify_email(token)
    result = VerificationService.verify_token(token)
    result[:success] && result[:user] == self
  end

  # Check if verification token is expired
  def verification_expired?
    VerificationService.token_expired?(self)
  end

  # Get verification status
  def verification_status
    VerificationService.verification_status(self)
  end

  # Generate JWT token for authentication
  def generate_jwt
    JwtService.encode(user_id: id)
  end

  # Check if welcome email has been sent
  def welcome_email_sent?
    welcome_email_sent_at.present?
  end

  # Check if welcome email is pending (waiting for verification)
  def pending_welcome_email?
    welcome_email_pending == true
  end

  # Check if user signed up with Google
  def google_signed_up?
    google_uid.present?
  end

  # Get full name
  def full_name
    [ first_name, last_name ].compact.join(" ").presence || email.split("@").first
  end

  # Get unread notification count
  def unread_notification_count
    notifications.where(read: false).count
  end

  # Get active warranties count (including component warranties)
  def active_warranties_count
    item_warranties.where("expires_at > ?", Date.current).count
  end

  # Get expiring soon warranties count
  def expiring_soon_count
    item_warranties.where("expires_at BETWEEN ? AND ?", Date.current, 30.days.from_now.to_date).count
  end

  # Get expired warranties count
  def expired_count
    item_warranties.where("expires_at < ?", Date.current).count
  end

  # Get dashboard summary
  def dashboard_summary
    {
      total_invoices: invoices.count,
      total_warranties: item_warranties.count,
      active_warranties: active_warranties_count,
      expiring_soon: expiring_soon_count,
      expired: expired_count,
      unread_notifications: unread_notification_count
    }
  end

  # Find or create user from Google OAuth
  def self.find_or_create_by_google_oauth!(auth)
    user = find_by(google_uid: auth.uid) || find_or_initialize_by(email: auth.info.email&.downcase)
    user.google_uid = auth.uid
    user.first_name ||= auth.info.first_name || auth.info.name&.split(" ")&.first || "User"
    user.last_name ||= auth.info.last_name || auth.info.name&.split(" ")&.last
    user.avatar_url = auth.info.image if auth.info.image.present?
    user.email_verified = true
    user.password = SecureRandom.hex(20) if user.new_record?
    user.role ||= :member
    user.save!
    user
  end

  private

  def password_required?
    !google_signed_up? || password.present?
  end

  def downcase_email
    self.email = email.downcase
  end
end
