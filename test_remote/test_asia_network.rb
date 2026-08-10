class AsiaNetworkTest < Minitest::Test
  def test_asia_network
    url = "#{$api}/api/sections/7f5913a2-bc18-48cf-84e5-4797573795b6/content_units"
    h = headers
    h['Accept'] = 'application/vnd.rise_api.v2, application/json'
    response = Faraday.get(url, nil, h)
    assert_equal(200, response.status)
    if response.status == 200
      r = JSON.parse(response.body)
      refute_empty(r)
      assert_includes(r.first, 'contents')
    end
  end
  def test_asia_network_header
    url = "download/text-for-asia-network/LC/LC0001/LC0001_001.txt"
    text = get_text(url)
    assert_includes(text, '#【經文資訊】呂澂佛學著作集 第 1 冊 No. 1 印度佛學源流略講', "純文字檔檔頭錯誤")
  end
end
