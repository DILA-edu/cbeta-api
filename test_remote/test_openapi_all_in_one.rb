require 'minitest/autorun'
require 'json_schemer'
require 'yaml'

# 以 doc/openapi.yaml 驗證線上 search/all_in_one 的回應。
# schema 一律 additionalProperties: false，API 多出或少掉欄位就會失敗。
class OpenapiAllInOneTest < Minitest::Test
  OPENAPI = JSONSchemer.openapi(YAML.safe_load_file(File.expand_path('../doc/openapi.yaml', __dir__)))
  RESPONSE_200 = OPENAPI.ref(
    '#/paths/~1search~1all_in_one/get/responses/200/content/application~1json/schema'
  )

  def setup
    @url = 'search/all_in_one'
  end

  def test_default
    r = assert_conform(q: '法鼓', rows: 2)
    refute_empty r['results']
    refute_includes r, 'facet'
  end

  def test_facet
    r = assert_conform(q: '法鼓', rows: 1, facet: '1')
    assert_includes r, 'facet'
  end

  def test_without_notes_and_cache
    r = assert_conform(q: '法鼓', rows: 1, note: '0', cache: '0')
    assert_nil r['cache_key']
  end

  def test_fields
    r = assert_conform(q: '法鼓', rows: 1, fields: 'work,juan,term_hits')
    assert_equal %w[juan term_hits work], r['results'].first.keys.sort
  end

  # KWIC 要讀 work 與 juan、行首資訊要讀 work；fields 沒列這些欄位時不應該因此出錯。
  # NEAR 與 Exclude 走另一條 code path，一併驗證。
  def test_fields_with_kwics
    r = assert_conform(q: '法鼓', rows: 1, fields: 'work,kwics')
    assert_equal %w[kwics work], r['results'].first.keys.sort

    [ '"法鼓" NEAR/5 "迦葉"', '"法鼓" -"大法鼓"' ].each do |q|
      r = assert_conform(q:, rows: 1, fields: 'juan,kwics')
      assert_equal %w[juan kwics], r['results'].first.keys.sort, q
    end
  end

  def test_filter_and_order
    assert_conform(q: '法鼓', rows: 1, canon: 'T', order: 'time_from-')
  end

  # NEAR 與 Exclude 走另一條 code path（先取回全部符合的卷，KWIC 過濾後才分頁），
  # facet 也由 Ruby 端另外計算。
  def test_near
    assert_conform(q: '"法鼓" NEAR/5 "迦葉"', rows: 1)
  end

  def test_near_with_facet
    r = assert_conform(q: '"法鼓" NEAR/5 "迦葉"', rows: 1, facet: '1')
    assert_includes r, 'facet'
  end

  def test_exclude
    assert_conform(q: '"法鼓" -"大法鼓"', rows: 1)
  end

  def test_exclude_with_facet
    r = assert_conform(q: '"法鼓" -"大法鼓"', rows: 1, facet: '1')
    assert_includes r, 'facet'
  end

  def test_query_too_long
    r = assert_conform(q: '法' * 41)
    assert_includes r, 'error'
  end

  private

  def assert_conform(params)
    r = get_json(@url, params)
    errors = RESPONSE_200.validate(r).map { it['error'] }
    assert_empty errors, "#{@url} #{params.inspect} 的回應不符合 doc/openapi.yaml:\n#{errors.join("\n")}"
    r
  end
end
