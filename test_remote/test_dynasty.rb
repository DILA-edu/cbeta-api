class DynastyTest < Minitest::Test
  def test_dynasty
    url = "works"
    params = { dynasty: '唐' }
    r = get_json(url, params)
    assert_operator(r['num_found'], :>=, 892)
  end
end
