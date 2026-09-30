require 'minitest/autorun'
require_relative 'openapi_helper'

# 以 doc/openapi.yaml 驗證 tools 與 asia-network 的回應。
class OpenapiToolsTest < Minitest::Test
  include OpenapiHelper

  def test_sc2tc
    r = assert_text('chinese_tools/sc2tc', 'text/plain', q: '简体转繁体')
    assert_equal '簡體轉繁體', r
  end

  def test_word_seg
    r = assert_text('word_seg', 'text/plain', t: '觀自在菩薩')
    assert_equal '/觀自在菩薩/', r.strip
  end

  def test_word_seg2
    r = assert_conform('word_seg2', { payload: '觀自在菩薩，行深般若波羅蜜多時。' })
    assert_includes r['segmented'], '觀自在菩薩'

    r = assert_conform('word_seg2', { payload: '觀' })
    assert_equal [ '觀' ], r['segmented']
  end

  def test_word_seg2_without_payload
    r = assert_conform('word_seg2')
    assert_equal 400, r.dig('error', 'code')
  end

  def test_textref_meta
    r = assert_text('textref/meta.csv', 'text/csv')
    assert_equal 'Field,Value', r.lines.first.strip
  end

  def test_textref_data
    r = assert_text('textref/data.csv', 'text/csv')
    assert_match(/\Aprimary_id,title,dynasty,author,edition,/, r)
  end

  # uuid 一層一層由上一層的回應取得。挑典籍最少的藏經，避免回應過大。
  def test_asia_network
    collections = assert_conform('api/collections')
    canon = collections.min_by { it['resourceCount'] }

    resources = assert_conform("api/collections/#{canon['uuid']}/resources",
                               path: '/api/collections/{uuid}/resources')
    refute_empty resources

    sections = assert_conform("api/resources/#{resources.first['uuid']}/sections",
                              path: '/api/resources/{uuid}/sections')
    refute_empty sections
    uuid = sections.first['uuid']

    section = assert_conform("api/sections/#{uuid}", path: '/api/sections/{uuid}')
    units = assert_conform("api/sections/#{uuid}/content_units", path: '/api/sections/{uuid}/content_units')
    assert_kind_of Array, units, '找不到該卷的文字檔'
    assert_equal section['uuid'], units.first['uuid']
    refute_empty units.first['contents']
  end

  private

  # 非 JSON 的回應: 驗 HTTP status 與 content type，回傳 body
  def assert_text(url, content_type, params = {})
    response = api_get("#{$api}/#{url}", params)
    assert_http_ok(response, url, params)
    assert_match(/\A#{Regexp.escape(content_type)}\b/, response.headers['content-type'], url)
    response.body.force_encoding('UTF-8')
  end
end
