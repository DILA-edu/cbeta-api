require 'test_helper'

class ChineseToolsControllerTest < ActionDispatch::IntegrationTest
  test "should get sc2tc" do
    get chinese_tools_sc2tc_url
    assert_response :success
  end

  test 'sc2tc 超過長度上限時回 400, 不執行 opencc' do
    post chinese_tools_sc2tc_url, params: { q: '佛' * (ApplicationController::MAX_TOOL_INPUT_LENGTH + 1) }

    assert_response :bad_request
    assert_match(/不得大於/, response.body)
  end
end
