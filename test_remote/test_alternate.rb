class TestAlternate < Minitest::Test
  def setup
    @url = "catalog_entry"
  end

  def test_alternate    
    params = { q: 'orig-X.001.001.002'}
    r = get_json(@url, params)
    assert_match(/X0002 ?\(=T0320\)/, r['results'][0]['label'])
  end

  def test_juan_start
    # JA003 從第7卷 開始
    params = { q: 'orig-J.001.003'}
    r = get_json(@url, params)
    j = r.dig('results', 0, 'juan_start')
    assert_equal(7, j)
  end
end
