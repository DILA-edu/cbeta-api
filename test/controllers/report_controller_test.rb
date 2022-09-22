require 'test_helper'

class ReportControllerTest < ActionDispatch::IntegrationTest
  test "should get access" do
    get report_daily_url
    assert_response :success
  end

end
