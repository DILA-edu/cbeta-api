class TocTest < Minitest::Test
  def setup
    @url = "works/toc"
  end

  def test_across_vol
    r = get_json(@url, work: 'B0088')
    assert_equal(55, r['results'][0]['juan'][0]['juan'], "B0088 第一卷應為 55")
  end

  def test_search_toc_by_work
    r = get_json(@url, work: 'JB483')
    title = r['results'][0]['juan'][5]['title']
    msg = "取得「典籍內目次」，其中 卷目次 第六卷 應為「第六」"
    assert_equal('第六', title, msg)  
  end
end
