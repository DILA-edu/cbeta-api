# frozen_string_literal: true

require 'test_helper'

# 流量報表限管理者;index (字數統計說明頁) 例外開放。
class ReportControllerTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:github] = nil
  end

  def sign_in(admin:, uid: '1')
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: 'github', uid:, info: { email: "#{uid}@example.com", name: 'A' }
    )
    get '/auth/github/callback'
    User.find_by!(provider: 'github', uid:).update!(admin:)
  end

  # --- 未登入 ---

  test '未登入時流量報表導向登入頁' do
    %i[report_daily_url report_url_url report_referer_url].each do |helper|
      get send(helper)
      assert_redirected_to login_path, "#{helper} 應該要求登入"
    end
  end

  test '未登入也能看字數統計說明頁' do
    get reports_url
    assert_response :success
  end

  # --- 已登入但非 admin ---

  test '非 admin 看流量報表得到 403' do
    sign_in(admin: false)

    get report_daily_url
    assert_response :forbidden
  end

  test '非 admin 也能看字數統計說明頁' do
    sign_in(admin: false)

    get reports_url
    assert_response :success
  end

  # --- admin ---

  test 'admin 可以看流量報表' do
    sign_in(admin: true)

    get report_daily_url
    assert_response :success
  end

  test 'admin 可以看 group by url 與 referer 報表' do
    sign_in(admin: true)

    get report_url_url
    assert_response :success

    get report_referer_url
    assert_response :success
  end

  test 'admin 可以匯出 CSV' do
    sign_in(admin: true)

    get report_daily_url(format: 'csv')
    assert_response :success
    assert_equal 'text/csv', response.media_type
  end

  test '非 admin 不能匯出 CSV' do
    sign_in(admin: false)

    get report_daily_url(format: 'csv')
    assert_response :forbidden
  end
end
