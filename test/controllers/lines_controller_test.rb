require 'test_helper'

class LinesControllerTest < ActionController::TestCase
  test 'linehead 不存在又帶 before/after 時回空結果, 不回 500' do
    get :index, params: { linehead: 'T01n0001_p9999a99', before: 0, after: 2 }

    assert_response :success
    assert_equal 0, response.parsed_body['num_found']
  end

  test 'linehead 存在時 after 會帶出後續行' do
    get :index, params: { linehead: 'T01n0001_p0001a01', before: 0, after: 1 }

    assert_response :success
    assert_equal %w[T01n0001_p0001a01 T01n0001_p0001a02],
                 response.parsed_body['results'].map { it['linehead'] }
  end
end
