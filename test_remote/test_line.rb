class LineTest < Minitest::Test
  def test_get_line_range
    url = "lines"
    params = { linehead: 'T01n0001_p0001a04' }
    r = get_json(url, params)
    refute_operator(r['num_found'], :<, 1)
  end
end
