require 'test_helper'

# GotoService 從 ApplicationController / JuansController 抽出來,
# 這裡鎖住各種輸入格式解析後的結果, 確保後續改動不會走樣。
class GotoServiceTest < ActiveSupport::TestCase
  setup do
    @service = GotoService.new
  end

  test "行首資訊格式" do
    r = @service.linehead(linehead: "T09n0262_p0056c02")

    assert_equal "T09", r[:vol]
    assert_equal "T0262", r[:work]
    assert_equal "T09n0262", r[:file]
    assert_equal "0056c02", r[:lb]
    assert_equal 7, r[:juan]
    assert_equal "T09n0262_p0056c02", r[:linehead]
  end

  test "行首資訊前後的空白會被忽略" do
    r = @service.linehead(linehead: "  T01n0001_p0001a01  ")
    assert_equal "T01n0001_p0001a01", r[:linehead]
  end

  test "linehead_start 參數" do
    r = @service.linehead(linehead_start: "T01n0001_p0001a02")
    assert_equal "T01n0001_p0001a02", r[:linehead]
  end

  test "CBETA 引用格式" do
    r = @service.linehead(linehead: "CBETA, T01, no. 1, p. 1, a1")

    assert_equal "T0001", r[:work]
    assert_equal "0001a01", r[:lb]
    assert_equal 1, r[:juan]
  end

  test "CBETA 2017 新引用格式" do
    r = @service.linehead(linehead: "CBETA 2019.Q2, T01, no. 1, p. 1a2")

    assert_equal "T0001", r[:work]
    assert_equal "0001a02", r[:lb]
  end

  test "論文引用慣例" do
    r = @service.linehead(linehead: "T01, no. 1, p. 1a1")

    assert_equal "T0001", r[:work]
    assert_equal "0001a01", r[:lb]
  end

  test "《大正藏》冊、號、卷 格式" do
    # 舊版本這條路徑沒把 work 參數傳進去, 一律回 404。
    r = @service.linehead(linehead: "《大正藏》冊1，第1 號，卷1")

    assert_nil r[:error]
    assert_equal "T0001", r[:work]
    assert_equal 1, r[:juan]
  end

  test "《大正藏》冊、號、頁 格式" do
    r = @service.linehead(linehead: "《大正藏》冊1，第1 號，頁1a1")

    assert_equal "T0001", r[:work]
    assert_equal "0001a01", r[:lb]
  end

  test "格式錯誤且不是已知縮寫時回傳 400" do
    r = @service.linehead(linehead: "不是行首資訊")

    assert_equal 400, r.dig(:error, :code)
  end

  test "CBETA 裡不存在的行首資訊回傳 404" do
    r = @service.linehead(linehead: "T01n0001_p9999a01")

    assert_equal 404, r.dig(:error, :code)
  end

  test "by_work 自己算 work id, 不必呼叫端先設好" do
    r = @service.by_work(canon: "T", work: "1", juan: 1)

    assert_equal "T0001", r[:work]
    assert_equal "T01", r[:vol]
    assert_equal 1, r[:juan]
  end

  test "by_work 找不到典籍時回傳 404" do
    r = @service.by_work(canon: "T", work: "9999", juan: 1)

    assert_equal 404, r.dig(:error, :code)
  end

  test "get_linehead 組出行首資訊字串" do
    assert_equal "T01n0001_p0001a01",
                 GotoService.get_linehead("T0001", "T01n0001", "0001a01")
    # 經號結尾是英文字母的不加底線
    assert_equal "T85n2865ap0001a01",
                 GotoService.get_linehead("T2865a", "T85n2865a", "0001a01")
    # T0220 的分冊檔名要去掉結尾字母
    assert_equal "T05n0220_p0001a01",
                 GotoService.get_linehead("T0220", "T05n0220a", "0001a01")
  end
end
