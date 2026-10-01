require 'test_helper'

# all_in_one 的 fields 參數。KWIC 要讀 work / juan、行首資訊要讀 work，
# 因此要等這些都算完才依 fields 過濾欄位；先過濾會 500。
# 本機沒有 Elasticsearch 與完整的 KWIC 資料，這裡把兩者換成假的，
# 其餘 (init、all_in_one_sub、行首資訊) 都走真的 code。
class SearchAllInOneFieldsTest < ActionDispatch::IntegrationTest
  ROW = {
    id: 5832, term_hits: 1, canon: 'T', category: '阿含部類', file: 'T01n0026',
    work: 'T0026', juan: 47, title: '中阿含經', byline: '東晉 瞿曇僧伽提婆譯',
    creators: '僧伽提婆', creators_with_id: '僧伽提婆(A001589)', time_dynasty: '東晉',
    time_from: 397, time_to: 398, juan_list: '1,2'
  }.freeze

  KWIC = { 'vol' => 'T01', 'lb' => '0724c01', 'kwic' => '多鼓、<mark>法鼓</mark>、甘露鼓' }.freeze

  class FakeSearchService
    def search(query, **)
      { query_string: query.raw, time: 0, num_found: 1, total_term_hits: 1,
        cache_key: nil, results: [ ROW.dup ] }
    end

    def all_candidates(*, **) = [ ROW.dup ]
    def exclude_search(query, **) = search(query)
  end

  class FakeKwicService
    def search(*) = { num_found: 1, results: [ KWIC.merge('work' => 'T0026', 'juan' => 47) ] }
    def search_near(*) = { num_found: 1, results: [ KWIC.dup ] }
  end

  test 'fields 沒列 juan 時仍回傳 KWIC 與行首資訊' do
    body = all_in_one(q: '法鼓', fields: 'work,kwics')

    assert_response :success
    result = body['results'].first
    assert_equal %w[kwics work], result.keys.sort
    assert_equal 'T01n0026_p0724c01', result.dig('kwics', 'results', 0, 'linehead')
  end

  test 'NEAR 的 fields 沒列 work 時仍回傳行首資訊' do
    body = all_in_one(q: '"法鼓" NEAR/5 "迦葉"', fields: 'juan,kwics')

    assert_response :success
    result = body['results'].first
    assert_equal %w[juan kwics], result.keys.sort
    assert_equal 'T01n0026_p0724c01', result.dig('kwics', 'results', 0, 'linehead')
  end

  test 'fields 沒列 kwics 時不跑 KWIC，只回傳指定欄位' do
    body = all_in_one(q: '法鼓', fields: 'work,juan,term_hits')

    assert_response :success
    assert_equal %w[juan term_hits work], body['results'].first.keys.sort
  end

  # NEAR / Exclude 的 facet 由 Ruby 端 my_facet 計算，部類也要有 category_id
  test 'NEAR 的 category facet 有 category_id' do
    Canon.create!(id2: 'T', name: '大正藏')
    body = all_in_one(q: '"法鼓" NEAR/5 "迦葉"', facet: '1')

    assert_response :success
    assert_equal [ { 'category_id' => 1, 'category_name' => '阿含部類', 'hits' => 1, 'docs' => 1 } ],
                 body.dig('facet', 'category')
  end

  test 'fields 只列 kwics 時只回傳 kwics' do
    body = all_in_one(q: '法鼓', fields: 'kwics')

    assert_response :success
    assert_equal %w[kwics], body['results'].first.keys
  end

  private

  def all_in_one(params)
    replace_new(CbetaSearch::SearchService, FakeSearchService.new) do
      replace_new(KwicService, FakeKwicService.new) do
        get '/search/all_in_one', params: params.merge(cache: '0', rows: 1)
      end
    end
    JSON.parse(response.body)
  end

  # Minitest 6 的 stub 已拆到 minitest-mock gem，這裡自己暫時換掉 .new。
  # 移除 singleton method 後就回到繼承自 Class 的原本 .new。
  def replace_new(klass, instance)
    klass.define_singleton_method(:new) { |*, **| instance }
    yield
  ensure
    klass.singleton_class.remove_method(:new)
  end
end
