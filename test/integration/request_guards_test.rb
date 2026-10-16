require 'test_helper'

# 全域 before_action 與 JSONP、行數上限等防護: 不合常規的輸入不應變成 500,
# 也不應讓單一 request 撈出整張表。
class RequestGuardsTest < ActionDispatch::IntegrationTest
  LH1 = 'T01n0001_p0001a01'.freeze
  LH2 = 'T01n0001_p0001a02'.freeze

  # --- Referer ---

  test '空字串或無 host 的 Referer 不會讓 request 失敗' do
    [ '', '/', '//' ].each do |referer|
      get '/lines', params: { linehead: LH1 }, headers: { 'Referer' => referer }

      assert_response :success, "Referer: #{referer.inspect}"
      assert_equal 1, response.parsed_body['num_found']
    end
  end

  test 'visits 記錄 Referer 的 host (含 port), 沒有 Referer 時記錄 IP' do
    get '/lines', params: { linehead: LH1 }, headers: { 'Referer' => 'https://example.org:8080/a/b' }
    get '/lines', params: { linehead: LH1 }, headers: { 'Referer' => '' }

    referers = Visit.where(url: '/lines', accessed_at: Date.today).pluck(:referer)
    assert_includes referers, 'example.org:8080'
    assert_includes referers, '127.0.0.1'
  end

  # 2026-10-16 起不再依 referer 屏蔽太虛 (TX)、印順 (Y)，由各網站自行判斷
  test '.cn 的 Referer 不再過濾內容' do
    Line.create!(linehead: 'Y01n0001_p0001a01', work: 'Y0001', vol: 'Y01', juan: 1, ser_no: 100, html: '')

    get '/lines', params: { linehead: 'Y01n0001_p0001a01' }, headers: { 'Referer' => 'https://example.cn/' }
    assert_equal 1, response.parsed_body['num_found']
  end

  test 'visits 寫入失敗不影響 API 回應' do
    # sanitize_sql_array 是繼承來的 class method, 移除 singleton method 即還原
    Visit.define_singleton_method(:sanitize_sql_array) { |*| raise ActiveRecord::StatementInvalid, 'analytics down' }

    get '/lines', params: { linehead: LH1 }

    assert_response :success
    assert_equal 1, response.parsed_body['num_found']
  ensure
    Visit.singleton_class.remove_method(:sanitize_sql_array)
  end

  # --- JSONP callback ---

  test '合法的 callback 會包裝回應' do
    get '/lines', params: { linehead: LH1, callback: 'jQuery123_456.cb' }

    assert_response :success
    assert_match(/\A\/\*\*\/jQuery123_456\.cb\(/, response.body)
  end

  test '不合法的 callback 不反射進回應, 改回一般 JSON' do
    get '/lines', params: { linehead: LH1, callback: 'alert(1);x' }

    assert_response :success
    assert_no_match(/alert/, response.body)
    assert_equal 1, response.parsed_body['num_found']
  end

  test 'CbetaError 的錯誤回應也驗證 callback' do
    get '/lines', params: { linehead: LH1, before: '-1', callback: 'alert(1);x' }

    assert_response :bad_request
    assert_no_match(/alert/, response.body)
  end

  # --- lines 行數上限 ---

  test 'before / after 在上限內照常回傳' do
    get '/lines', params: { linehead: LH2, before: '1', after: '0' }

    assert_response :success
    assert_equal([ LH1, LH2 ], response.parsed_body['results'].map { it['linehead'] })
  end

  test 'before / after 為負數或超過上限時回 400' do
    [ { before: '-1' }, { after: (LinesController::MAX_LINES + 1).to_s } ].each do |extra|
      get '/lines', params: { linehead: LH1, **extra }
      assert_response :bad_request, extra.inspect
    end
  end

  test 'linehead 範圍在上限內照常回傳' do
    get '/lines', params: { linehead_start: LH1, linehead_end: LH2 }

    assert_response :success
    assert_equal 2, response.parsed_body['num_found']
  end

  test 'linehead 範圍超過上限時回 400' do
    with_max_lines(1) do
      get '/lines', params: { linehead_start: LH1, linehead_end: LH2 }
    end

    assert_response :bad_request
  end

  private

  def with_max_lines(n)
    original = LinesController::MAX_LINES
    silence_warnings { LinesController.const_set(:MAX_LINES, n) }
    yield
  ensure
    silence_warnings { LinesController.const_set(:MAX_LINES, original) }
  end
end
