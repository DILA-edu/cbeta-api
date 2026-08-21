# frozen_string_literal: true

# 同時記 user 與 key 兩個維度: key 會輪替,只記 per-key 會在 rotation 時斷掉;
# 但要追查「哪把 key 外流」又必須知道是哪把 key。
#
# 見 doc/api-key-design.md 4.4
class CreateApiKeyUsages < ActiveRecord::Migration[8.1]
  def change
    create_table :api_key_usages do |t|
      t.references :user,    null: false
      t.references :api_key, null: false
      t.date       :used_on, null: false
      t.integer    :count,   null: false, default: 0
    end

    add_index :api_key_usages, [:api_key_id, :used_on], unique: true
    add_index :api_key_usages, [:user_id, :used_on]
  end
end
