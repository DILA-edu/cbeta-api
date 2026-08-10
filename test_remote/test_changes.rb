class ChangeTest < Minitest::Test
  def setup
    @url = "changes"
  end

  def test_work
    params = { work: 'T0026' }
    r = get_json(@url, params)
    refute_nil(r)
    assert_includes(r, "num_found")
  end
end
