require 'test_helper'

# search/title: ES 回傳的每筆結果補上 Work 的經錄資訊。
# 本機沒有 Elasticsearch, 把 SearchService 換成假的, 其餘走真的 code。
class SearchTitleTest < ActionDispatch::IntegrationTest
  class FakeSearchService
    def search(*, **)
      { num_found: 2, cache_key: 'x', results: [
        { work: 'T0001', content: '長阿含經' },
        { work: 'T9999', content: '不存在的經' }
      ] }
    end
  end

  test '結果補上 Work 資訊, 查無 Work 的筆維持原樣' do
    CbetaSearch::SearchService.define_singleton_method(:new) { |*, **| FakeSearchService.new }
    get '/search/title', params: { q: '長阿含經' }

    assert_response :success
    found, missing = response.parsed_body['results']
    assert_equal '後秦 佛陀耶舍共竺佛念譯', found['byline']
    assert_equal 22, found['juan']
    assert_equal 384, found['time_from']
    refute missing.key?('byline')
    refute response.parsed_body.key?('cache_key')
  ensure
    CbetaSearch::SearchService.singleton_class.remove_method(:new)
  end
end
