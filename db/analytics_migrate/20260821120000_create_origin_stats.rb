# frozen_string_literal: true

# 過渡期埋點。
#
# 過渡期結束時,若 cbetaonline 前端實際上沒送 Origin,前端會全站掛掉。
# 需在過渡期就蒐證,不必等前端工程師回覆。
#
# 放 analytics DB: 純統計、量小、不需 join users。
#
# 見 doc/api-key-design.md 4.5
class CreateOriginStats < ActiveRecord::Migration[8.1]
  def change
    create_table :origin_stats do |t|
      t.string  :origin,  null: false # Origin 為 nil 時記為 "(none)"
      t.date    :used_on, null: false
      t.integer :count,   null: false, default: 0
    end

    add_index :origin_stats, [:origin, :used_on], unique: true
  end
end
