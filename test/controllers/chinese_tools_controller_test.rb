require 'test_helper'

class ChineseToolsControllerTest < ActionDispatch::IntegrationTest
  test "should get sc2tc" do
    get chinese_tools_sc2tc_url
    assert_response :success
  end

end
