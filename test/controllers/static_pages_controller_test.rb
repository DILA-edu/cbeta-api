require 'test_helper'

class StaticPagesControllerTest < ActionDispatch::IntegrationTest
  # 全文檢索說明頁應正常 render，並標示 q 長度上限（取自 MAX_QUERY_LENGTH）。
  SEARCH_DOC_PAGES = %w[
    search
    search_all_in_one
    search_extended
    search_notes
    search_facet
    search_synonym
    search_similar
    search_title
    search_vars
    search_kwic
    search_toc
  ].freeze

  SEARCH_DOC_PAGES.each do |page|
    test "static_pages/#{page} 顯示 q 長度上限" do
      get "/static_pages/#{page}"
      assert_response :success
      assert_includes response.body, "長度上限為 #{ApplicationController::MAX_QUERY_LENGTH} 字"
    end
  end

  # 這四個 endpoint 的 q 參數行為相同（都走 CbetaSearch::QueryParser:
  # 整個 q 不含雙引號時一律當成一個詞組，連 NEAR 都不會被解析成運算子），
  # 說明因此共用 _q-quotes.haml。
  #
  # 漏掉任何一頁，使用者就會以為那個 endpoint 的語法不一樣 —— 舊版 notes
  # 正是這樣長出「請注意上面的雙引號不可省略」這句與其他頁不一致的但書
  # （見 doc/elasticsearch-migration.md 的 F-1 第 7 項）。
  QUOTE_RULE_PAGES = {
    'search' => '/search',
    'search_extended' => '/search/extended',
    'search_notes' => '/search/notes',
    'search_all_in_one' => '/search/all_in_one'
  }.freeze

  QUOTE_RULE_PAGES.each do |page, path|
    test "static_pages/#{page} 說明 q 的雙引號規則, 且範例指向自己的 endpoint" do
      get "/static_pages/#{page}"

      assert_response :success
      assert_includes response.body, '單一個詞可以不加雙引號'
      assert_includes response.body,
                      'AND、OR、NOT、NEAR、Exclude 語法的每個詞都必須用雙引號括起來'
      assert_includes response.body, "#{path}?q=法鼓"
    end
  end

  test 'search_notes 不再保留與其他頁不一致的雙引號但書' do
    get '/static_pages/search_notes'

    assert_response :success
    assert_not_includes response.body, '雙引號不可省略'
  end

  # search/sc 有更嚴格的 50 字上限，說明頁需呈現該值。
  test "static_pages/search_sc 顯示 50 字上限" do
    get '/static_pages/search_sc'
    assert_response :success
    assert_includes response.body, '長度上限為 50 字'
  end

  # API key 說明頁的額度數字必須跟實際生效的常數一致，
  # 否則調整額度時說明頁會靜默過期。
  test 'static_pages/api_key 顯示的額度與實際設定一致' do
    get '/static_pages/api_key'
    assert_response :success
    assert_includes response.body, ApiKeyAuthentication::ANONYMOUS_LIMIT.to_s
    assert_includes response.body, ApiKeyAuthentication::KEYED_LIMIT.to_s
    assert_includes response.body, 'Authorization: Bearer'
  end

  test 'static_pages/api_key 不需要 API key 就能看' do
    original = Rails.configuration.api_key_required
    Rails.configuration.api_key_required = true

    get '/static_pages/api_key'
    assert_response :success
  ensure
    Rails.configuration.api_key_required = original
  end
end
