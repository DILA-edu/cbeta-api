require 'minitest/autorun'
require_relative 'openapi_helper'

# 以 doc/openapi.yaml 驗證 search/sc、similar、synonym、variants 的回應。
class OpenapiSearchBTest < Minitest::Test
  include OpenapiHelper

  def test_sc
    r = assert_conform('search/sc', { q: '四圣谛' })
    assert_equal '四聖諦', r['q']
    refute_equal 0, r['hits']

    assert_conform('search/sc', { q: '四圣谛', canon: 'T', note: '0' })
  end

  # 繁簡相同時不檢索，也不回傳 time
  def test_sc_unchanged
    r = assert_conform('search/sc', { q: '上烏' })
    assert_equal({ 'q' => '上烏', 'hits' => 0 }, r)
  end

  def test_sc_query_too_long
    r = assert_conform('search/sc', { q: '圣' * 41 })
    assert_includes r, 'error'
  end

  # similar 用 cache (預設)，重複執行時不必重算
  def test_similar
    r = assert_conform('search/similar', { q: '是日已過，命亦隨減，如少水魚，斯有何樂' })
    refute_empty r['results']
    refute_includes r, 'facet'
  end

  def test_similar_with_facet
    r = assert_conform('search/similar', { q: '是日已過，命亦隨減，如少水魚，斯有何樂', facet: '1' })
    assert_includes r, 'facet'
  end

  def test_similar_invalid_param
    r = assert_conform('search/similar', { q: '是日已過命亦隨減', k: '0' })
    assert_includes r, 'error'
  end

  def test_synonym
    r = assert_conform('search/synonym', { q: '文殊師利' })
    refute_empty r['results']

    r = assert_conform('search/synonym', { q: '不存在的詞' })
    assert_empty r['results']
  end

  def test_variants
    r = assert_conform('search/variants', { q: '著衣持鉢' })
    refute_empty r['results']

    r = assert_conform('search/variants', { q: '著衣持鉢', cache: '0' })
    assert_nil r['cache_key']

    assert_conform('search/variants', { q: '神咒', scope: 'title' })
    assert_conform('search/variants', { q: '著衣持鉢', canon: 'T' })
  end

  def test_variants_query_too_long
    r = assert_conform('search/variants', { q: '著' * 41 })
    assert_includes r, 'error'
  end
end
