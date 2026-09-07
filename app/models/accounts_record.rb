# frozen_string_literal: true

# 使用者與 API key 資料的 base class。
#
# 為什麼要獨立一個 database:
# primary(內容)DB 每年隨 CBETA 資料更新全部清掉重建 2~3 次,使用者資料
# 絕對不能放 primary。也不放 analytics —— 語意不符,且備份策略不同:
# analytics 掉了可以重跑統計,users / api_keys 掉了所有人的 key 立即失效。
#
# 見 doc/api-key-design.md 4.1、doc/annual-rotation.md。
class AccountsRecord < ApplicationRecord
  self.abstract_class = true
  connects_to database: { writing: :accounts, reading: :accounts }
end
