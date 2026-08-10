class LayerTest < Minitest::Test
  def test_layer
    url = "juans"
    params = { work: 'GA0089', juan: 19 }
    r = get_json(url, params)
    html = r['results'].first
    regexp = /<a [^>]*class="place_start"[^>]*"><\/a>檇李<a [^>]*class="place_end"[^>]*">/
    assert_match(regexp, html, 'GA0089_019應含地名')
  end
end
