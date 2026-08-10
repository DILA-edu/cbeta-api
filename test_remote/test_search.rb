require 'minitest/autorun'
class SearchTest < Minitest::Test
  # 2024.R1 開始，要能搜到 U+2F8BB, 這是 CB22057 的 Unicode
  def test_2F8BB
    url = "search"
    params = { q: '捨' } # U+2F8BB
    r = get_json(url, params)
    refute_equal(0, r['num_found'], "搜不到 U+2F8BB")
  end

  def test_2F94
    url = "search"
    params = { q: '⾔' } # U+2F94
    r = get_json(url, params)
    assert_equal(0, r['num_found'], "不應搜到 '⾔'(U+2F94)")
  end

  def test_search
    url = "search"
    params = { q: '亦如毒樹' }
    r = get_json(url, params)
    refute_equal(0, r['num_found'])
    
    # CB00146
    params = { q: "[幻-ㄠ+糸]" }
    r = get_json(url, params)
    refute_equal(0, r['num_found'])
    
    # 半形空格區隔的外文
    params = { q: 'Pāli Text Society' }
    r = get_json(url, params)
    refute_equal(0, r['num_found'])  

    # 含 單引號
    #params = { q: %q(samantato \'nantanāvāptiśāsani) }
    params = { q: "samantato \\'nantanāvāptiśāsani" }
    r = get_json(url, params)
    refute_equal(0, r['num_found'])  

    # 含 雙引號
    #params = { q: %q(Your \"mang\-kun\") }
    params = { q: 'Your \"mang\-kun\"' }
    r = get_json(url, params)
    refute_equal(0, r['num_found'])  
  end

  def test_search_footnote
    url = "search/notes"
    ['法鼓', '上烏罪反下他罪反', '[虺-虫+畏]', '掩【宋】【元】'].each do |q|
      params = { q: %("#{q}") }
      r = get_json(url, params)
      refute_equal(0, r['num_found'], "search/notes 搜不到 '#{q}'")
    end
  end
  
  def test_search_title
    url = "search/title"
    params = { q: '雲棲法彙' }
    r = get_json(url, params)
    refute_equal(0, r['num_found'])
  end

  def test_sc
    url = "search/sc"
    params = { q: '四圣谛' }
    r = get_json(url, params)
    refute_nil(r)
  end

  def test_similar
    url = "search/similar"
    params = { q: '諸惡莫作，眾善奉行，自淨其意，是諸佛教' }
    r = get_json(url, params)
    refute_includes(r, 'error', "回傳 error: #{r['error']}")
  end

  def test_variants
    url = "search/variants"
    params = { q: '壺' }
    r = get_json(url, params)
    r['results'].each do |h|
      refute_equal('壼', h['q'], "壺 與 壼 不應有異體關係!")
    end
  end
end
