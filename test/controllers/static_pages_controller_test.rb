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

  # search/sc 有更嚴格的 50 字上限，說明頁需呈現該值。
  test "static_pages/search_sc 顯示 50 字上限" do
    get '/static_pages/search_sc'
    assert_response :success
    assert_includes response.body, '長度上限為 50 字'
  end
end
