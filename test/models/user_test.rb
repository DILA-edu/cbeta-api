# frozen_string_literal: true

require 'test_helper'

class UserTest < ActiveSupport::TestCase
  # 只用到 from_omniauth 會碰的介面,不依賴 omniauth gem
  Info = Struct.new(:email, :name)
  Auth = Struct.new(:provider, :uid, :info)

  def auth_hash(provider: 'github', uid: '12345', email: 'a@example.com', name: 'A')
    Auth.new(provider, uid, Info.new(email, name))
  end

  test 'provider 必須是支援的 provider' do
    user = User.new(provider: 'facebook', uid: '1')
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :provider
  end

  test 'provider + uid 唯一' do
    User.create!(provider: 'github', uid: '1')
    dup = User.new(provider: 'github', uid: '1')
    assert_not dup.valid?
  end

  test '同一個 uid 在不同 provider 是兩個獨立帳號' do
    User.create!(provider: 'github', uid: '1')
    assert User.new(provider: 'google_oauth2', uid: '1').valid?
  end

  test 'from_omniauth 建立新 user' do
    user = User.from_omniauth(auth_hash)
    assert_equal 'github', user.provider
    assert_equal '12345', user.uid
    assert_equal 'a@example.com', user.email
  end

  test 'from_omniauth 對既有 user 更新 email 與 name' do
    User.from_omniauth(auth_hash)
    user = User.from_omniauth(auth_hash(email: 'b@example.com', name: 'B'))
    assert_equal 1, User.where(provider: 'github', uid: '12345').count
    assert_equal 'b@example.com', user.email
    assert_equal 'B', user.name
  end

  test 'from_omniauth 容許 email 為 nil (GitHub 可能設為 private)' do
    user = User.from_omniauth(auth_hash(email: nil))
    assert_nil user.email
    assert user.persisted?
  end

  test 'can_create_api_key? 在達到上限後為 false' do
    user = User.create!(provider: 'github', uid: '1')
    assert user.can_create_api_key?

    User::MAX_ACTIVE_API_KEYS.times { ApiKey.generate!(user) }
    assert_not user.can_create_api_key?
  end

  test '撤銷後可以再產生' do
    user = User.create!(provider: 'github', uid: '1')
    keys = User::MAX_ACTIVE_API_KEYS.times.map { ApiKey.generate!(user).first }
    keys.first.revoke!
    assert user.can_create_api_key?
  end

  test 'display_name 依序 fallback' do
    assert_equal 'A', User.new(name: 'A', email: 'a@example.com').display_name
    assert_equal 'a@example.com', User.new(email: 'a@example.com').display_name
    assert_equal 'github:1', User.new(provider: 'github', uid: '1').display_name
  end
end
