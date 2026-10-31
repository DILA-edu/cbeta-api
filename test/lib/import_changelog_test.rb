require 'test_helper'

# `ImportChangelog` 定義在 lib/tasks/import/changelog.rake 裡
Rails.application.load_tasks unless defined?(ImportChangelog)

class ImportChangelogTest < ActiveSupport::TestCase
  # scan 有 capture group 時 block 收到 [字串], 原本 x.size 永遠是 1, 算成 span 數
  test 'ins_chars / del_chars 是字數, 不是 span 數' do
    importer = ImportChangelog.allocate # 不跑 initialize: 它會覆寫 log 檔
    html = '<span class="ins">abcd</span>x<span class="ins">e[口*牙]</span><span class="del">甲乙</span>'

    assert_equal 6, importer.send(:count, html, 'ins'), '組字式算一個字'
    assert_equal 2, importer.send(:count, html, 'del')
  end
end
