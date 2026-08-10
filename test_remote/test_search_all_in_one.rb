require 'minitest/autorun'

class SearchAllInOneTest < Minitest::Test
  def setup
    @url = "search/all_in_one"
  end

  def test_category
    params = { q: '法鼓', category: '阿含部類' }
    r = get_json(@url, params)
    refute_equal(0, r['num_found'])
    refute_includes(r, 'error', "search all_in_one 部類 錯誤")
  end

  def test_all_in_one_without_notes
    params = { q: '一切賢聖皆以無為法而有差別盖謂法本不無', note: '0' }
    r = get_json(@url, params)
    refute_empty(r['results'], '跨夾注搜尋失敗')
  end

  def test_all_in_one_fields
    params = { 
      q: '法鼓', 
      fields: "work,juan,term_hits" 
    }
    get_json(@url, params)
  end
  
  def test_juan_across_vol
    # X0714 卷3 跨冊
    params = { q: '舍利', work: 'X0714' }
    r = get_json(@url, params)
    assert_operator(4, :>=, r['num_found'], "search all_in_one X0714 卷3 跨冊, 回傳卷數不應超過4")
  end

  def test_search_all_in_one
    params = { q: '法鼓', facet: '1' }
    r = get_json(@url, params)
    refute_equal(0, r['num_found'])
  
    params = { q: '和尚', facet: '1' }
    r = get_text(@url, params)
    assert_includes(r, '義淨', "search all_in_one facet creator_name 錯誤")

    # AND
    params = { q: '"法鼓" "迦葉"' }
    r = get_json(@url, params)
    refute_empty(r['results'], "search all_in_one AND 發生錯誤")

    # NEAR 範圍重疊
    params = { q: '"意樂" NEAR/7 "增上意樂"' }
    r = get_json(@url, params)
    refute_includes(r, 'error', "search near 發生錯誤")
  
    # NEAR, 指定 rows 時，回傳 num_found 是否正確
    params = { q: '"老子" NEAR/7 "道" NEAR/7 "經"', rows: 10 }
    r = get_json(@url, params)
    assert_operator(r['num_found'], :>, 10)

    # escape 單引號
    params = { q: %q("samantato" "\'nantanāvāptiśāsani") }
    r = get_json(@url, params)
    refute_equal(0, r['num_found'])  

    # escape 雙引號、半形減號
    params = { q: %q("Your" "\"mang\-kun\"") }
    r = get_json(@url, params)
    refute_equal(0, r['num_found'])

    # 不分大小寫
    params = { q: 'Bhagini' }
    r = get_json(@url, params)
    refute_empty(r['results'], "search 搜尋 Bhagini 結果不應為空。")
  end

  def test_special_char
    ['一城□□□', '明▆相'].each do |q|
      params = { q: }
      r = get_json(@url, params)
      refute_empty(r['results'], "search 搜尋 #{q} 結果不應為空。")
      assert_equal(r['num_found'], r['results'].size)
    end
  end
end
