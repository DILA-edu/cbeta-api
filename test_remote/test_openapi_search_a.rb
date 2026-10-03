require 'minitest/autorun'
require_relative 'openapi_helper'

# 以 OpenAPI spec 驗證 /search、/search/extended、/search/facet(/{facet_by})、
# /search/notes、/search/title 的回應。
class OpenapiSearchATest < Minitest::Test
  include OpenapiHelper

  def test_search
    r = assert_conform('search', { q: '法鼓', rows: 1 })
    refute_empty r['results']
  end

  def test_search_fields_and_order
    r = assert_conform('search', { q: '法鼓', rows: 1, fields: 'work,juan', order: 'time_from-' })
    assert_equal %w[juan work], r['results'].first.keys.sort
  end

  def test_search_filter
    assert_conform('search', { q: '法鼓', rows: 1, canon: 'T', note: '0' })
  end

  # NEAR 與 Exclude 的 term_hits 由另一條路徑計算
  def test_search_near_and_exclude
    assert_conform('search', { q: '"法鼓" NEAR/5 "迦葉"', rows: 1 })
    assert_conform('search', { q: '"法鼓" -"大法鼓"', rows: 1 })
  end

  # 去除標點後為空
  def test_search_only_punctuation
    r = assert_conform('search', { q: '，' })
    assert_equal 0, r['num_found']
  end

  def test_search_query_too_long
    r = assert_conform('search', { q: '法' * 41 })
    assert_includes r, 'error'
  end

  def test_extended
    assert_conform('search/extended', { q: '"法鼓" "迦葉"', rows: 1 })
    assert_conform('search/extended', { q: '"法鼓" | "迦葉"', rows: 1 })
  end

  def test_facet
    %w[canon category creator dynasty work].each do |facet_by|
      r = assert_conform("search/facet/#{facet_by}", { q: '法鼓' }, path: '/search/facet/{facet_by}')
      refute_empty r, facet_by
    end
  end

  def test_facet_all
    r = assert_conform('search/facet', { q: '法鼓' })
    assert_equal %w[canon category creator dynasty work], r.keys.sort
  end

  def test_facet_errors
    path = '/search/facet/{facet_by}'
    r = assert_conform('search/facet/xxx', { q: '法鼓' }, path:)
    assert_includes r, 'error'

    r = assert_conform('search/facet/work', { q: '"法鼓" NEAR/5 "迦葉"' }, path:)
    assert_includes r, 'error'
  end

  def test_notes
    r = assert_conform('search/notes', { q: '法鼓', rows: 1 })
    refute_empty r['results']
  end

  # 夾注 (inline) 沒有 n 欄位，highlight 附上前後文
  def test_notes_inline
    r = assert_conform('search/notes', { q: '迷私反', rows: 5, around: '5' })
    assert(r['results'].any? { it['note_place'] == 'inline' })
  end

  def test_notes_facet
    r = assert_conform('search/notes', { q: '法鼓', rows: 1, facet: '1' })
    assert_includes r, 'facet'
  end

  def test_notes_near_and_exclude
    assert_conform('search/notes', { q: '"法鼓" NEAR/5 "經"', rows: 1 })
    assert_conform('search/notes', { q: '"法鼓" -"大法鼓"', rows: 1 })
  end

  def test_title
    r = assert_conform('search/title', { q: '觀無量壽經', rows: 2 })
    refute_empty r['results']
  end

  def test_title_filter
    assert_conform('search/title', { q: '法鼓', rows: 2, canon: 'T' })
  end

  def test_invalid_order_and_grouping
    r = assert_conform('search', { q: '法鼓', order: 'year' })
    assert_match(/不支援的欄位/, r['error'])

    r = assert_conform('search/notes', { q: '("法鼓" | "印順") "迦葉"' })
    assert_match(/不支援括號分組/, r['error'])
  end
end
