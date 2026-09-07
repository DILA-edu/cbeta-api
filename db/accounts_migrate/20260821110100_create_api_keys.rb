# frozen_string_literal: true

# 見 doc/api-key-design.md 4.3
class CreateApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :api_keys do |t|
      t.references :user, null: false
      # 不存明文,只存 Digest::SHA256.hexdigest(token)。
      # 明文僅在產生當下顯示一次。
      t.string   :token_digest, null: false
      # 帳號頁要「只顯示前綴」讓使用者辨識是哪一把 key(設計文件 5.4),
      # 但 digest 無法反推前綴,故另存前綴。
      # 只存 "cbeta_" + 6 碼,對 32 bytes 隨機的 token 而言洩漏量可忽略,
      # 且與 GitHub / Stripe 顯示 key 前綴的慣例一致。
      t.string   :token_hint, null: false
      t.datetime :last_used_at
      # 撤銷用軟刪除(設 revoked_at),保留稽核紀錄,不硬刪
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :api_keys, :token_digest, unique: true
    add_index :api_keys, [:user_id, :revoked_at]
  end
end
