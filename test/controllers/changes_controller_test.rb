require 'test_helper'

class ChangesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Change.create!(work: 'T0001', juan: 1, lb: 'T01n0001_p0001a01', ver: '2026R1', html: 'a')
    Change.create!(work: 'T0262', juan: 1, lb: 'T09n0262_p0001a01', ver: '2026R1', html: 'b')
  end

  teardown do
    Change.delete_all
  end

  # lb[]=x 不算 blank, 但會被 permit 丟掉; 原本因此變成 Change.where({}) 回傳整張表
  test 'lb 為 array 時視同未帶參數, 不回傳整張表' do
    [ { lb: [ 'x' ] }, { lb: { k: 'v' } } ].each do |params|
      get '/changes', params: params

      assert_match(/不能都是空的/, response.body)
      assert_no_match(/T09n0262/, response.body)
    end
  end

  test 'juan 為 array 時不應 500' do
    get '/changes', params: { work: 'T0001', juan: [ '1' ] }

    assert_response :success
  end

  test '依 work 查詢只回傳該部佛典' do
    get '/changes', params: { work: 'T0001' }

    assert_response :success
    assert_equal([ 'T01n0001_p0001a01' ], response.parsed_body['results'].map { it['lb'] })
  end
end
