require 'test_helper'

# 鎖住 filter 與排序的 Elasticsearch query body，
# 語意對應舊 SearchController 的 set_filter / init_order。
class CbetaSearch::ElasticQueryBuilderTest < ActiveSupport::TestCase
  setup do
    @builder = CbetaSearch::ElasticQueryBuilder.new
    @parser = CbetaSearch::QueryParser.new
  end

  def filters_for(params)
    body = @builder.filtered_query(@parser.parse('法鼓'), params:, field: 'content')
    body['bool']['filter'] || []
  end

  test '單值 filter 用 term, 多值用 terms' do
    assert_includes filters_for(canon: 'T'), { 'term' => { 'canon' => 'T' } }
    assert_includes filters_for(canon: 'T,X'), { 'terms' => { 'canon' => %w[T X] } }
  end

  test 'works 優先於 work' do
    assert_includes filters_for(work: 'T0001', works: 'T0002,T0003'),
                    { 'terms' => { 'work' => %w[T0002 T0003] } }
  end

  test 'category 以部類名稱轉成 category_ids' do
    assert_includes filters_for(category: '阿含部類'),
                    { 'term' => { 'category_ids' => 1 } }
  end

  test 'category 的 a,b+c,d 是 (a OR b) AND (c OR d)' do
    filters = filters_for(category: '阿含部類,本緣部類+本緣部類')

    assert_includes filters, { 'terms' => { 'category_ids' => [1, 2] } }
    assert_includes filters, { 'term' => { 'category_ids' => 2 } }
  end

  test 'category 名稱不存在時該群組被忽略' do
    assert_empty filters_for(category: '不存在的部類')
  end

  test 'creator 去掉 A 與前導零' do
    assert_includes filters_for(creator: 'A001583'), { 'terms' => { 'creator_id' => [1583] } }
  end

  test 'time 單一年代與區間' do
    assert_equal [{ 'range' => { 'time_from' => { 'lte' => 650 } } },
                  { 'range' => { 'time_to' => { 'gte' => 650 } } }],
                 filters_for(time: '650')
    assert_equal [{ 'range' => { 'time_from' => { 'lte' => 700 } } },
                  { 'range' => { 'time_to' => { 'gte' => 600 } } }],
                 filters_for(time: '600..700')
  end

  test 'referer 是 .cn 時屏蔽 cn_filter 的藏經' do
    builder = CbetaSearch::ElasticQueryBuilder.new(referer_cn: true)
    body = builder.filtered_query(@parser.parse('法鼓'), params: {}, field: 'content')

    assert_equal [{ 'terms' => { 'canon' => Rails.configuration.cn_filter } }],
                 body['bool']['must_not']
  end

  test '無 order 參數時用指定的預設排序' do
    assert_equal CbetaSearch::ElasticQueryBuilder::DEFAULT_SORT, @builder.sort({})
    assert_equal [{ '_score' => { 'order' => 'desc' } }] +
                 CbetaSearch::ElasticQueryBuilder::DEFAULT_SORT,
                 @builder.sort({}, default: CbetaSearch::ElasticQueryBuilder::SCORE_SORT)
  end

  test 'canon 排序用 canon_order' do
    assert_equal 'canon_order', @builder.sort({ order: 'canon' }).first.keys.first
  end

  test 'term_hits 排序預設遞減, 對應 _score' do
    assert_equal({ '_score' => { 'order' => 'desc' } }, @builder.sort({ order: 'term_hits' }).first)
  end

  test '排序方向以 + - 指定' do
    assert_equal({ 'work' => { 'order' => 'desc' } }, @builder.sort({ order: 'work-' }).first)
    assert_equal({ 'work' => { 'order' => 'asc' } }, @builder.sort({ order: 'work+' }).first)
  end

  test 'time_from 排序時先讓有年代的排在前面' do
    clauses = @builder.sort({ order: 'time_from' })

    assert_equal 'asc', clauses[0]['_script']['order']
    assert_equal({ 'time_from' => { 'order' => 'asc' } }, clauses[1])
  end

  test '未知的排序欄位被忽略, 全部無效時退回預設' do
    assert_equal({ 'work' => { 'order' => 'asc' } }, @builder.sort({ order: 'nonexistent,work' }).first)
    assert_equal CbetaSearch::ElasticQueryBuilder::DEFAULT_SORT, @builder.sort({ order: 'nonexistent' })
  end

  # 舊版 Manticore 平手時是不可預期的內部順序，這裡改成穩定的排序。
  test '排序一律補上 canon_order / work / juan 作為平手時的比較依據' do
    clauses = @builder.sort({ order: 'term_hits' })

    assert_equal %w[_score canon_order work juan], clauses.flat_map(&:keys)
  end

  test '已指定的欄位不會被 tiebreaker 重複附加' do
    clauses = @builder.sort({ order: 'work-' })

    assert_equal %w[work canon_order juan], clauses.flat_map(&:keys)
  end

  test 'phrase 查詢用 script_score 把 _score 除以 token 數' do
    body = @builder.match_query(@parser.parse('法鼓'), field: 'content')

    assert_equal '_score / 2', body['script_score']['script']['source']
    assert_equal '法鼓', body['script_score']['query']['match_phrase']['content']['query']
  end

  test '連續的拉丁字母是一個 token, 除數要跟著改變' do
    body = @builder.match_query(@parser.parse('Ānanda'), field: 'content')
    assert_equal '_score / 1', body['script_score']['script']['source']

    body = @builder.match_query(@parser.parse('Pāli Text Society'), field: 'content')
    assert_equal '_score / 3', body['script_score']['script']['source']
  end

  test 'NEAR 多詞以左結合的巢狀 all_of 表達' do
    body = @builder.match_query(@parser.parse('"老子" NEAR/7 "道" NEAR/3 "經"'), field: 'content')
    outer = body['intervals']['content']['all_of']

    assert_equal 3, outer['max_gaps']
    assert_equal 7, outer['intervals'][0]['all_of']['max_gaps']
    assert_equal '經', outer['intervals'][1]['match']['query']
  end

  test 'Exclude 用 not_contained_by 排除被完整字串包含的出現' do
    body = @builder.match_query(@parser.parse('"舍利" -"舍利弗"'), field: 'content')
    match = body['intervals']['content']['match']

    assert_equal '舍利', match['query']
    assert_equal '舍利弗', match['filter']['not_contained_by']['match']['query']
  end

  test 'NEAR 與 Exclude 的 phrase interval 必須明寫 ordered 與 max_gaps' do
    body = @builder.match_query(@parser.parse('"法鼓" NEAR/7 "迦葉"'), field: 'content')
    inner = body['intervals']['content']['all_of']['intervals'].first['match']

    assert_equal true, inner['ordered']
    assert_equal 0, inner['max_gaps']
  end

  test 'note=0 查 content_without_notes 欄位' do
    body = @builder.match_query(@parser.parse('法鼓'), field: 'content_without_notes')

    assert body['script_score']['query']['match_phrase'].key?('content_without_notes')
  end
end
