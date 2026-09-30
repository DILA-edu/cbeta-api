require 'minitest/autorun'
require_relative 'openapi_helper'

# 以 OpenAPI spec 驗證 catalog 類 API 的回應:
# works、works/toc、toc、search/toc、catalog_entry、changes、export/all_creators2
class OpenapiCatalogTest < Minitest::Test
  include OpenapiHelper

  def test_works_by_work
    r = assert_conform('works', { work: 'T1501' })
    assert_equal 'T1501', r['results'].first['work']
    assert_includes r['results'].first, 'places'
  end

  # CBETA 未收錄全文的佛典: 有 alt，juan_list 等為 null
  def test_works_alt
    r = assert_conform('works', { work: 'JA001' })
    assert_equal 'T0293', r['results'].first['alt']
  end

  def test_works_not_found
    r = assert_conform('works', { work: 'T9999' })
    assert_equal 0, r['num_found']
  end

  def test_works_ranges
    assert_conform('works', { canon: 'T', vol_start: 1, vol_end: 1 })
    assert_conform('works', { canon: 'T', work_start: 1, work_end: 2 })
    assert_conform('works', { time_start: 600, time_end: 601 })
  end

  def test_works_by_creator
    assert_conform('works', { creator_id: 'A000439' })
    assert_conform('works', { creator: '竺法護' })
    assert_conform('works', { dynasty: '符秦' })
  end

  # 只搜尋尚未確認作譯者 ID 的佛典
  def test_works_by_creator_name
    assert_conform('works', { creator_name: '竺' })
  end

  def test_works_by_canon_uuid
    r = assert_conform('works', { uuid: 'c64eee93-3c77-4b26-8bf2-602dd1352fad' })
    refute_empty r
  end

  def test_works_param_errors
    [
      { work: 'XYZ' },
      { canon: 'T', vol_start: 'a' },
      { work_start: 'T0001' },
      { dynasty: 'abc' },
      { time_start: 'a', time_end: 601 }
    ].each do |params|
      r = assert_conform('works', params)
      assert_equal 400, r.dig('error', 'code'), params.inspect
    end
  end

  def test_works_toc
    r = assert_conform('works/toc', { work: 'T0001' })
    refute_empty r['results'].first['mulu']

    r = assert_conform('works/toc', { work: 'T9999' })
    assert_empty r['results']
  end

  def test_toc
    r = assert_conform('toc', { q: '大本經' })
    assert_includes r['results'].map { it['type'] }, 'toc'

    r = assert_conform('toc', { q: '阿含部' })
    assert_includes r['results'].map { it['type'] }, 'catalog'
  end

  def test_toc_by_work_id
    r = assert_conform('toc', { q: 'T0001' })
    assert_equal 'work', r['results'].first['type']

    r = assert_conform('toc', { q: 'T01n0001' })
    assert_equal 'T0001', r['results'].first['work']
  end

  def test_toc_errors
    assert_includes assert_conform('toc', { q: '' }), 'error'
    assert_includes assert_conform('toc', { q: '法' * 41 }), 'error'
  end

  def test_search_toc
    r = assert_conform('search/toc', { q: '大本經' })
    refute_empty r['results']
  end

  def test_catalog_entry
    assert_conform('catalog_entry')
    assert_conform('catalog_entry', { q: 'root' })

    r = assert_conform('catalog_entry', { q: 'CBETA.001.001' })
    assert_includes r['results'].map { it['node_type'] }, 'work'

    r = assert_conform('catalog_entry', { q: 'orig-J.001' })
    assert_includes r['results'].map { it['node_type'] }, 'alt'

    r = assert_conform('catalog_entry', { q: 'CBETA.022' })
    assert_includes r['results'].map { it['node_type'] }, 'html'

    r = assert_conform('catalog_entry', { q: 'nope' })
    assert_empty r['results']
  end

  def test_catalog_entry_by_vol
    r = assert_conform('catalog_entry', { vol: 'T01' })
    refute_empty r['results']
  end

  def test_changes
    r = assert_conform('changes', { lb: 'A091n1057_p0321a10' })
    refute_empty r['results']

    r = assert_conform('changes', { work: 'T0951', juan: 4 })
    refute_empty r['results']
  end

  def test_changes_errors
    assert_includes assert_conform('changes'), 'error'
    assert_includes assert_conform('changes', { juan: 1, lb: 'A091n1057_p0321a10' }), 'error'
  end

  def test_changes_html
    html = get_text('changes', { work: 'T0951', juan: 4, format: 'html' })
    assert_match(/<h2>\d{4}R\d<\/h2>/, html)
  end

  def test_export_all_creators
    r = assert_conform('export/all_creators2')
    assert_equal r['num_found'], r['results'].size
  end
end
