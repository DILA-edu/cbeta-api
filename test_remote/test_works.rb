class WorksTest < Minitest::Test
  def setup
    @url = "works"
  end

  def test_search_author_by_id
    params = { creator_id: 'A000439' }
    r = get_json(@url, params)
    refute_operator(r['num_found'], :<, 6)
  end

  def test_works
    r = get_text(@url, work: 'T0001', callback: 'jQuery999')
    refute_nil(r)
    
    r = get_json(@url, work: 'T1562')
    h = r['results'][0]
    refute_empty(h['category'], "T1562 的 category 不應空白")  
    refute_empty(h['orig_category'], "T1562的 orig_category 不應空白")
  
    r = get_json(@url, work: 'T1851')
    h = r['results'][0]
    assert_equal('諸宗部', h['orig_category'], "T1851 的 orig_category 應為 諸宗部")
  
    # 指定冊數起迄
    r = get_json(@url, canon: 'T', vol_start: 1, vol_end: 2)
    refute_nil(r)
  
    # 指定冊數起迄
    r = get_json(@url, canon: 'CC', vol_start: 1, vol_end: 1)
    refute_empty(r['results'], "canon: CC, 指定冊數起迄, 不應該回傳 empty array")

    # 指定 經號 起迄
    # 經號 英文字母 開頭
    r = get_json(@url, canon: 'ZW', work_start: 'a071')
    refute_equal(0, r['num_found'])
  end
end
