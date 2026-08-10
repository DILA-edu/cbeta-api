require 'minitest/autorun'

class SearchTocTest < Minitest::Test
  def setup
    @url = "search/toc"
  end

  def test_search_toc
    data = %w[大本經 金剛]
    data.each do |s|
      params = { q: s }
      r = get_json(@url, params)
      assert_operator(r['num_found'], :>, 0)
    end
  end
  
  # CBETA 部分收錄
  def test_search_toc_partial
    params = { q: "雲棲法彙" }
    r = get_json(@url, params)
    refute_empty(r['results'])
  end

  def test_check_file
    r = get_json(@url, q: '婆藪盤豆')
    toc = r['results'].first
    assert_equal('K35n1257', toc['file'])
  end
end
