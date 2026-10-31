class CatalogTest < Minitest::Test
  def setup
    @url = "catalog_entry"
  end

  def test_cbeta
    params = { q: 'CBETA' }
    r = get_json(@url, params)
    assert_equal(23, r['num_found'])

    params = { q: 'CBETA.023.006.003' }
    r = get_json(@url, params)
    label = r['results'][0]['label']
    refute_operator(label, :end_with?, '（上）')
  end

  def test_y
    params = { q: 'orig-Y.003' }
    data = get_json(@url, params)
    assert_equal('Y0030 雜阿含經論會編', data.dig('results', 0, 'label'))
  end
end
