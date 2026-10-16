require 'test_helper'

class ExportControllerTest < ActionDispatch::IntegrationTest
  # 2026-10-16 起 .cn 的 Referer 不再屏蔽太虛、印順
  test 'all_creators2 不依 Referer 過濾' do
    skip '缺少 data/all-creators-with-alias.json' unless Rails.root.join('data/all-creators-with-alias.json').file?

    get '/export/all_creators2'
    full = response.parsed_body

    get '/export/all_creators2', headers: { 'Referer' => 'https://example.cn/' }
    assert_equal full, response.parsed_body
  end
end
