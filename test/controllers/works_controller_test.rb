require 'test_helper'

class WorksControllerTest < ActionDispatch::IntegrationTest
  # work_start / work_end 是「經號」參數, 必須搭配 canon 使用, 例如
  # canon=T&work_start=1 代表 T0001。參數格式錯誤時要回 400,
  # 不可以靜默回傳錯誤範圍的資料。

  test "指定經號起迄" do
    get works_url, params: { canon: "T", work_start: 1, work_end: 9999 }
    assert_response :success

    r = JSON.parse(response.body)
    assert_equal %w[T0001 T0262], r["results"].map { it["work"] }
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
end
