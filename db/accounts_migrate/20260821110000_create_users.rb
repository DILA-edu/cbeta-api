# frozen_string_literal: true

# 見 doc/api-key-design.md 4.2
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      # identity 以 provider + uid 為準,email 僅作參考
      # (GitHub email 可能為 private 或 nil)
      t.string  :provider, null: false # "google_oauth2" | "github"
      t.string  :uid,      null: false
      t.string  :email
      t.string  :name
      t.boolean :admin, null: false, default: false

      t.timestamps
    end

    add_index :users, [:provider, :uid], unique: true
    add_index :users, :email
  end
end
