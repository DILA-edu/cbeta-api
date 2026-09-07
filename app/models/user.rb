# frozen_string_literal: true

# 以 Google 或 GitHub 帳號登入的使用者。
#
# identity 以 provider + uid 為準,email 僅作參考(GitHub email 可能為
# private 或 nil)。同一人用 Google 與 GitHub 分別登入視為兩個獨立帳號,
# 不自動合併。
#
# 見 doc/api-key-design.md 4.2
class User < AccountsRecord
  # 每個 user 同時最多幾把有效 key。
  # 2 把是為了支援無縫 rotation: 先建新 key → 換完 → 再撤銷舊 key。
  MAX_ACTIVE_API_KEYS = 2

  PROVIDERS = %w[google_oauth2 github].freeze

  has_many :api_keys, dependent: :destroy
  has_many :api_key_usages, dependent: :delete_all

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :uid, presence: true, uniqueness: { scope: :provider }

  # OmniAuth 的 auth hash 找出或建立對應的 user。
  # email / name 每次登入都更新,provider 端改了資料才能跟上。
  def self.from_omniauth(auth)
    user = find_or_initialize_by(provider: auth.provider, uid: auth.uid.to_s)
    user.email = auth.info&.email
    user.name  = auth.info&.name
    user.save!
    user
  end

  def active_api_keys
    api_keys.active.order(created_at: :desc)
  end

  def can_create_api_key?
    api_keys.active.count < MAX_ACTIVE_API_KEYS
  end

  def display_name
    name.presence || email.presence || "#{provider}:#{uid}"
  end
end
