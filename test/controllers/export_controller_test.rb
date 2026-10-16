require 'test_helper'

class ExportControllerTest < ActionDispatch::IntegrationTest
  CN_FILTERED = %w[A023393 A004819].freeze # 印順法師、太虛

  # 解析結果有快取, .cn 的過濾不可改到共用的資料, 否則之後的一般 request 也會少這兩位
  test 'all_creators2 的 .cn 過濾不影響之後的一般 request' do
    skip '缺少 data/all-creators-with-alias.json' unless Rails.root.join('data/all-creators-with-alias.json').file?

    get '/export/all_creators2'
    full = response.parsed_body

    get '/export/all_creators2', headers: { 'Referer' => 'https://example.cn/' }
    cn = response.parsed_body
    assert_equal full['num_found'] - CN_FILTERED.count { full['results'].key?(it) }, cn['num_found']
    CN_FILTERED.each { refute cn['results'].key?(it) }

    get '/export/all_creators2'
    assert_equal full, response.parsed_body
  end
end
