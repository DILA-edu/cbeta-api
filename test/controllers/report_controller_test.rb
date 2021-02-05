require 'test_helper'

class ReportControllerTest < ActionDispatch::IntegrationTest
  test "should get access" do
    get report_access_url
    assert_response :success
  end

end
