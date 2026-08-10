class TextrefTest < Minitest::Test
  def setup
    @url = 'textref'
  end

  def test_meta
    r = get_text("#{@url}/meta.csv")
    assert_includes(r, 'Field,Value', 'TextRef meta error')
  end

  def test_data
    r = get_text("#{@url}/data.csv")
    assert_includes(r, 'primary_id,title', 'TextRef data error')
  end
end
