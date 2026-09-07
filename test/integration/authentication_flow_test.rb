# frozen_string_literal: true

require 'test_helper'

# 登入、帳號頁、產生/撤銷 key 的整合測試。
class AuthenticationFlowTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: 'github',
      uid: '12345',
      info: { email: 'a@example.com', name: 'A' }
    )
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:github] = nil
  end

  def sign_in_via_github
    get '/auth/github/callback'
    follow_redirect!
  end

  test '登入頁不需登入即可看到' do
    get login_path
    assert_response :success
    assert_select 'h1', text: /登入/
  end

  test '登入頁有隱私權告知' do
    get login_path
    assert_match '隱私權告知', response.body
  end

  test '未登入時帳號頁導向登入頁' do
    get account_path
    assert_redirected_to login_path
  end

  test 'callback 會建立 user 並導向帳號頁' do
    assert_difference 'User.count', 1 do
      get '/auth/github/callback'
    end
    assert_redirected_to account_path
    assert_equal 'github', User.last.provider
  end

  test '登入後可以看到帳號頁' do
    sign_in_via_github
    assert_response :success
    assert_match '我的帳號', response.body
  end

  test '再次登入不會建立第二個 user' do
    get '/auth/github/callback'
    reset!
    OmniAuth.config.test_mode = true
    assert_no_difference 'User.count' do
      get '/auth/github/callback'
    end
  end

  test '登入後導回原本要去的頁面' do
    get account_path # 未登入 → 記下 return_to
    get '/auth/github/callback'
    assert_redirected_to account_path
  end

  test '登入失敗導回登入頁' do
    get '/auth/failure', params: { message: 'invalid_credentials' }
    assert_redirected_to login_path
  end

  test '登出後帳號頁又需要登入' do
    sign_in_via_github
    post logout_path
    get account_path
    assert_redirected_to login_path
  end

  test '產生 key，明文只顯示一次' do
    sign_in_via_github

    assert_difference 'ApiKey.count', 1 do
      post account_api_keys_path
    end
    follow_redirect!

    token = flash[:new_api_key]
    assert token.start_with?(ApiKey::TOKEN_PREFIX)
    assert_match token, response.body
    assert_select 'button[data-copy-target=?]', 'new-api-key'

    # 再開一次帳號頁就看不到明文了
    get account_path
    assert_no_match token, response.body
  end

  test '超過上限時產生 key 被拒' do
    sign_in_via_github
    User::MAX_ACTIVE_API_KEYS.times { post account_api_keys_path }

    assert_no_difference 'ApiKey.count' do
      post account_api_keys_path
    end
    follow_redirect!
    assert_match '最多', response.body
  end

  test '可以撤銷自己的 key' do
    sign_in_via_github
    post account_api_keys_path
    api_key = ApiKey.last

    delete account_api_key_path(api_key)
    assert_not api_key.reload.active?
  end

  test '不能撤銷別人的 key' do
    other = User.create!(provider: 'google_oauth2', uid: '999')
    other_key, = ApiKey.generate!(other)

    sign_in_via_github
    delete account_api_key_path(other_key)

    assert other_key.reload.active?
  end

  test '未登入不能產生 key' do
    assert_no_difference 'ApiKey.count' do
      post account_api_keys_path
    end
    assert_redirected_to login_path
  end

  test '帳號頁顯示 key 前綴但不顯示明文' do
    sign_in_via_github
    post account_api_keys_path
    api_key = ApiKey.last

    get account_path
    assert_match api_key.token_hint, response.body
    assert_no_match api_key.token_digest, response.body
  end
end
