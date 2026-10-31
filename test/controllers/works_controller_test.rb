require 'test_helper'

class WorksControllerTest < ActionDispatch::IntegrationTest
  # work_start / work_end 是「經號」參數, 必須搭配 canon 使用, 例如
  # canon=T&work_start=1 代表 T0001。參數格式錯誤時要回 400,
  # 不可以靜默回傳錯誤範圍的資料。

  test "指定經號起迄" do
    get works_url, params: { canon: "T", work_start: 1, work_end: 9999 }
    assert_response :success

    r = JSON.parse(response.body)
    assert_equal(%w[T0001 T0262], r["results"].map { it["work"] })
  end

  test "省略 work_end 時只查單一經號" do
    get works_url, params: { canon: "T", work_start: 1 }
    assert_response :success

    r = JSON.parse(response.body)
    assert_equal 1, r["num_found"]
    assert_equal "T0001", r["results"].first["work"]
  end

  test "經號為 英文字母 開頭" do
    get works_url, params: { canon: "ZW", work_start: "a071" }
    assert_response :success

    r = JSON.parse(response.body)
    assert_nil r["error"]
  end

  test "work_start 誤傳完整典籍編號回傳 400" do
    get works_url, params: { canon: "T", work_start: "T0001" }
    assert_response :success

    r = JSON.parse(response.body)
    assert_equal 400, r.dig("error", "code")
  end

  test "work_start 未帶 canon 回傳 400" do
    get works_url, params: { work_start: "T0001", work_end: "T9999" }
    assert_response :success

    r = JSON.parse(response.body)
    assert_equal 400, r.dig("error", "code")
  end

  test "work_start 格式錯誤回傳 400" do
    get works_url, params: { canon: "T", work_start: "abc" }
    assert_response :success

    r = JSON.parse(response.body)
    assert_equal 400, r.dig("error", "code")
  end

  test "work_end 格式錯誤回傳 400" do
    get works_url, params: { canon: "T", work_start: 1, work_end: "T9999" }
    assert_response :success

    r = JSON.parse(response.body)
    assert_equal 400, r.dig("error", "code")
  end

  # creator 系列參數的 % _ 原本直接進 LIKE, creator=% 會回傳所有佛典
  test 'creator 參數含 % _ 時當成一般字元比對' do
    works(:t0001).update!(creators: '佛陀耶舍', creators_with_id: '佛陀耶舍(A000001)')
    %i[creator creator_id creator_name].each do |key|
      get '/works', params: { key => '%' }

      assert_response :success
      assert_equal 0, response.parsed_body['num_found'], key.to_s
    end
  end

  # 跨冊判斷原本要求佛典涵蓋整個查詢範圍, 查詢範圍放寬反而少了結果
  test '冊號範圍與跨冊佛典有重疊就回傳' do
    Work.create!(n: 'T0220', canon: 'T', vol: 'T05..T07', title: '大般若波羅蜜多經', juan_list: '1-600')

    [ [ 6, 6 ], [ 6, 8 ], [ 7, 8 ], [ 4, 6 ], [ 1, 9 ] ].each do |vs, ve|
      get '/works', params: { canon: 'T', vol_start: vs, vol_end: ve }

      assert_includes response.parsed_body['results'].map { it['work'] }, 'T0220', "#{vs}..#{ve}"
    end

    get '/works', params: { canon: 'T', vol_start: 8, vol_end: 9 }
    assert_not_includes response.parsed_body['results'].map { it['work'] }, 'T0220'
  end

  test 'time_start 少了 time_end 時回錯誤' do
    get '/works', params: { time_start: 300 }

    assert_equal 400, response.parsed_body.dig('error', 'code')
    assert_match(/time_end/, response.parsed_body.dig('error', 'message'))
  end

  test '數字參數為 array 時回 400 而不是 500' do
    get '/works', params: { time_start: [ '300' ], time_end: '500' }

    assert_equal 400, response.parsed_body.dig('error', 'code')
  end

end
