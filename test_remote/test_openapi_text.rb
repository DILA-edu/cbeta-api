require 'minitest/autorun'
require_relative 'openapi_helper'

# 以 OpenAPI spec 驗證 text 組 (search/kwic、lines、juans、juans/goto) 的回應。
class OpenapiTextTest < Minitest::Test
  include OpenapiHelper

  # --- search/kwic ---

  def test_kwic
    r = assert_conform('search/kwic', { work: 'X0600', juan: 11, q: '法鼓' })
    refute_empty r['results']
  end

  def test_kwic_multiple_keywords
    assert_conform('search/kwic', { work: 'X0600', juan: 11, q: '法鼓,聖嚴' })
  end

  def test_kwic_near
    r = assert_conform('search/kwic', { work: 'T1736', juan: 1, q: '"老子" NEAR/7 "道"' })
    refute_empty r['results']
  end

  def test_kwic_options
    r = assert_conform('search/kwic', { work: 'T0001', juan: 1, q: '法', around: 2,
                       mark: '1', kwic_wo_punc: '1', place: '1', note: '0' })
    hit = r['results'].first
    assert_includes hit, 'kwic_no_punc'
    assert_includes hit, 'place_name'
  end

  def test_kwic_without_punc
    r = assert_conform('search/kwic', { work: 'X0600', juan: 11, q: '法鼓', kwic_w_punc: '0' })
    refute_includes r['results'].first, 'kwic'
  end

  def test_kwic_negative_lookahead
    assert_conform('search/kwic', { work: 'T0001', juan: 17, q: '舍利', negative_lookahead: '弗' })
  end

  def test_kwic_errors
    [
      { juan: 1, q: '法' },                    # 缺 work
      { work: 'T9999', juan: 1, q: '法' },     # 佛典編號不存在
      { work: 'T0001', juan: 1, q: '法' * 41 } # q 過長
    ].each do |params|
      r = assert_conform('search/kwic', params)
      assert_includes r, 'error', params.inspect
    end
  end

  # --- lines ---

  def test_lines
    r = assert_conform('lines', { linehead: 'T01n0001_p0001a04' })
    assert_equal 1, r['num_found']
    assert_includes r['results'].first, 'notes'
  end

  def test_lines_before_after
    r = assert_conform('lines', { linehead: 'T01n0001_p0001a04', before: 1, after: 1 })
    assert_equal 3, r['num_found']
  end

  def test_lines_range
    r = assert_conform('lines', { linehead_start: 'T01n0001_p0001a04', linehead_end: 'T01n0001_p0001a06' })
    assert_equal 3, r['num_found']
  end

  def test_lines_not_found
    r = assert_conform('lines', { linehead: 'T01n0001_p9999a99' })
    assert_equal 0, r['num_found']
  end

  # --- juans ---

  def test_juans
    r = assert_conform('juans', { work: 'T0001', juan: 1 })
    assert_equal 1, r['num_found']
  end

  def test_juans_with_toc_and_work_info
    # T0279 的目次有多層巢狀
    r = assert_conform('juans', { work: 'T0279', juan: 1, toc: '1', work_info: '1' })
    assert_includes r, 'toc'
    assert_includes r, 'work_info'
  end

  def test_juans_not_found
    r = assert_conform('juans', { work: 'T0001', juan: 99 })
    assert_equal 0, r['num_found']
  end

  # --- juans/goto ---

  def test_goto_by_work
    [
      { canon: 'T', work: '1' },
      { canon: 'T', work: '1', juan: 2 },
      { canon: 'T', work: '1', page: '11', col: 'b', line: '10' }
    ].each do |params|
      r = assert_conform('juans/goto', params)
      assert_equal 1, r['num_found'], params.inspect
    end
  end

  def test_goto_by_vol
    [
      { canon: 'T', vol: '1' },
      { canon: 'T', vol: '1', page: '11', col: 'b', line: '10' }
    ].each do |params|
      r = assert_conform('juans/goto', params)
      assert_equal 1, r['num_found'], params.inspect
    end
  end

  def test_goto_by_linehead
    [
      'T01n0001_p0066c25',
      'CBETA, T01, no. 1, p. 67, a13',
      'CBETA 2019.Q3, T30, no. 1579, p. 279a7-23'
    ].each do |linehead|
      r = assert_conform('juans/goto', { linehead: })
      assert_equal 1, r['num_found'], linehead
    end
  end

  def test_goto_errors
    [
      { linehead: 'xyz' },                 # 格式錯誤
      { linehead: 'T01n0001_p9999a01' },   # 行首資訊不存在
      { canon: 'T', work: '99999' },       # 佛典編號不存在
      { canon: 'T', work: '1', page: '0' } # 頁碼不存在
    ].each do |params|
      r = assert_conform('juans/goto', params)
      assert_includes r, 'error', params.inspect
    end
  end
end
