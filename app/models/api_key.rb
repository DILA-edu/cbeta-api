# frozen_string_literal: true

# API key。
#
# 不存明文,只存 SHA256 digest;明文僅在產生當下回傳一次。
# 撤銷用軟刪除(設 revoked_at),保留稽核紀錄。
#
# 刻意不加 Redis cache: 驗證是 token_digest unique index 的單筆查詢,
# 而加了 cache 就必須處理撤銷失效,「刪了還能用幾分鐘」對「懷疑外流要立刻
# 止血」這個核心需求是直接的功能缺陷。
#
# 見 doc/api-key-design.md 4.3
class ApiKey < AccountsRecord
  # 加前綴便於辨識,也有利於 secret scanning 工具偵測
  TOKEN_PREFIX = 'cbeta_'
  TOKEN_BYTES = 32

  # last_used_at 節流: 距上次更新超過這段時間才寫,避免每個 request 一次 UPDATE
  LAST_USED_THROTTLE = 1.hour

  # 顯示給使用者辨識用的前綴長度(TOKEN_PREFIX 之後再取幾碼)
  HINT_LENGTH = 6

  belongs_to :user
  has_many :api_key_usages, dependent: :delete_all

  validates :token_digest, presence: true, uniqueness: true
  validate  :active_keys_within_limit, on: :create

  scope :active, -> { where(revoked_at: nil) }

  # 產生一把新 key。明文只在這裡回傳,之後無法再取得。
  # 回傳 [api_key, plaintext_token]
  def self.generate!(user)
    token = "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(TOKEN_BYTES)}"
    api_key = create!(user:, token_digest: digest(token), token_hint: hint(token))
    [api_key, token]
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token)
  end

  def self.hint(token)
    token[0, TOKEN_PREFIX.length + HINT_LENGTH]
  end

  # 依明文找出有效的 key。找不到或已撤銷都回 nil。
  def self.authenticate(token)
    return nil if token.blank?

    active.find_by(token_digest: digest(token))
  end

  def active?
    revoked_at.nil?
  end

  def revoke!
    return false unless active?

    update!(revoked_at: Time.current)
  end

  # 用 update_column 跳過 callback 與 validation —— 這是每個 request 都會走的
  # 熱路徑,而且 validation 會再打一次 DB。
  def touch_last_used!(now = Time.current)
    return if last_used_at.present? && now - last_used_at < LAST_USED_THROTTLE

    update_column(:last_used_at, now)
  end

  private

  def active_keys_within_limit
    return if user.nil?
    return if user.api_keys.active.where.not(id:).count < User::MAX_ACTIVE_API_KEYS

    errors.add(:base, "同時最多只能有 #{User::MAX_ACTIVE_API_KEYS} 把有效的 API key，請先撤銷舊的")
  end
end
