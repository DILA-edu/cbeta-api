# frozen_string_literal: true

# doorkeeper 已移除（見 doc/api-key-design.md 2.4、7.1）。
# 這三張表從未存放正式資料：initializers/doorkeeper.rb 的
# resource_owner_authenticator 回傳假使用者，唯一的寫入端
# oauth/registrations_controller 其 route 是註解掉的。
class DropDoorkeeperTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :oauth_access_grants, if_exists: true
    drop_table :oauth_access_tokens, if_exists: true
    drop_table :oauth_applications, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'doorkeeper 已自專案移除，不再重建這些 table'
  end
end
