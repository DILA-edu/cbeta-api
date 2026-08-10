ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

class ActiveSupport::TestCase
  # test 環境使用獨立的 db/test.sqlite3 與 fixtures,不碰真實的 CBETA 資料。
  # 針對真實資料/線上 API 的測試放在 test_remote/ (rake remote:test)。
  fixtures :all

  # Add more helper methods to be used by all tests here...
end
