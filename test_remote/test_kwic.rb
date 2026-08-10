class KwicText < Minitest::Test
  def setup
    @url = "search/kwic"
  end

  def test_and
    params = { q: '法鼓,聖嚴', work: 'X0600', juan: 11 }
    r = get_json(@url, params)
    refute_equal(0, r['num_found'])  
  end

  def test_1
    params = { q: '裹真珠', work: 'M1540', juan: 2 }
    r = get_json(@url, params)
    assert_equal(1, r['num_found'], "kwic 結果 應只有一筆")
  end

  def test_kwic
    data = [
      { q: '丸散', work: 'T1911', juan: 5 },
      { q: '元氣', work: 'T1973', juan: 70 }, # T1973 沒有 70卷, 測試 API 能否正確回傳空值
      { around: 50, q: '夢', work: 'T2122', juan: 32, rows: 999, mark: 1 }
    ]
    data.each do |params|
      r = get_json(@url, params)
      refute_nil(r)
    end
  end

  def test_escape
    # escape 單引號
    #params = { work: 'T1645', juan: 2, q: %q(samantato \'nantanāvāptiśāsani) }
    params = { work: 'T1645', juan: 2, q: "samantato \\'nantanāvāptiśāsani" }
    r = get_json(@url, params)
    refute_equal(0, r['num_found'])  

    # escape 雙引號、半形減號
    #params = { work: 'B0170', juan: 3, q: %q(Your \"mang\-kun\") }
    params = { work: 'B0170', juan: 3, q: 'Your \"mang\-kun\"' }
    r = get_json(@url, params)
    refute_equal(0, r['num_found'])  
  end
  
  # 卷跨冊
  def test_cross_vol
    params = { q: '略申', work: 'L1557', juan: 17 }
    r = get_json(@url, params)
    kwic = r['results'][0]["kwic"]
    assert_match(/^.{5}略申.{5}$/, kwic)
  end

  def test_near
    params = { q: '"細中之" NEAR/15 "論疏唯"', work: 'D8859', juan: 3, note: 0 }
    r = get_json(@url, params)
    if r['num_found'] == 0
      refute_equal(0, r['num_found'], 'kwic near 跨夾注 錯誤')
    else
      assert_equal('0233b04', r['results'][0]["lb"])
    end
  
    # 範圍重疊
    params = { q: '"意樂" NEAR/7 "增上意樂"', work: 'T0187', juan: 1 }
    r = get_json(@url, params)
    assert_equal(0, r['num_found'])  
  end

  def test_cross_note
    # 跨夾注, 搜尋結果的起始行號在夾注裡
    params = { q: '拔猶預箭坦蕩自心', work: 'K1064', juan: 2, note: 0 }
    r = get_json(@url, params)
    assert_equal('0362c10', r['results'][0]["lb"])

    params = { q: '法門上卷按', work: 'D8859', juan: 3, note: 0, sort: 'location' }
    r = get_json(@url, params)
    assert_equal('0216b02', r['results'][0]["lb"])
  end

  def test_exclude
    params = { q: '直心', negative_lookbehind: '正', work: 'T0099', juan: 26 }
    r = get_json(@url, params)
    assert_equal(1, r['num_found'])
    assert_equal(1, r['results'].size)

    params = { q: '舍利', negative_lookahead: '弗', work: 'T0001', juan: 17 }
    r = get_json(@url, params)
    assert_equal(1, r['num_found'])
    assert_equal(1, r['results'].size)
  end
end
