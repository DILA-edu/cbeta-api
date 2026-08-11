require 'test_helper'

class JuansControllerTest < ActionDispatch::IntegrationTest
  # goto 的解析邏輯在 GotoService (見 test/services/goto_service_test.rb),
  # 這裡只確認 controller 有正確接上 service 並包成 API 格式。

  test "goto by linehead" do
    get juans_goto_url, params: { linehead: "T01n0001_p0001a01" }
    assert_response :success

    r = JSON.parse(response.body)
    assert_equal 1, r["num_found"]

    result = r["results"].first
    assert_equal "T0001", result["work"]
    assert_equal "T01n0001", result["file"]
    assert_equal 1, result["juan"]
    assert_equal "長阿含經", result["title"]
  end

  test "goto by canon and work" do
    get juans_goto_url, params: { canon: "T", work: "1", juan: "1" }
    assert_response :success

    r = JSON.parse(response.body)
    assert_equal 1, r["num_found"]
    assert_equal "T0001", r["results"].first["work"]
  end

  test "goto 格式錯誤回傳 400" do
    get juans_goto_url, params: { linehead: "不是行首資訊" }
    assert_response :success

    r = JSON.parse(response.body)
    assert_equal 400, r.dig("error", "code")
  end

  test "goto 找不到典籍回傳 404" do
    get juans_goto_url, params: { canon: "T", work: "9999", juan: "1" }
    assert_response :success

    r = JSON.parse(response.body)
    assert_equal 404, r.dig("error", "code")
  end
end
