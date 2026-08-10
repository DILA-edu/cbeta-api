require 'cbeta'

class GotoTest < Minitest::Test
  def setup
    @url = "juans/goto"
  end

  def test_goto
    params = { canon: 'T', work: 1 }
    r = get_json(@url, params)
    assert_includes(r, 'num_found')
    refute_operator(r['num_found'], :<, 1)
  
    # 頁碼 開頭 英文字母
    params = {canon: 'ZW', vol: 10, page: 'b008'}
    r = get_json(@url, params)
    refute_operator(r['num_found'], :<, 1)
  end

  def test_goto_vol
    params = { canon: 'B', vol: 14 }
    r = get_json(@url, params)
    assert_equal('0001a01', r['results'][0]['lb'])

    params = { canon: 'M', vol: 49 }
    r = get_json(@url, params)
  end

  def test_goto_vol_page
    params = { canon: 'T', vol: 9, page: 198, col: 'b' }
    r = get_json(@url, params)
    refute_includes(r, 'error', "goto 發生錯誤: #{params}")

    params = {canon: "T", vol: 8, page: "9", line: "1", col: "c", work: "224"}
    r = get_json(@url, params)
    assert_includes(r, 'error', "work id 不符，goto 應該要回傳錯誤: #{params}")
  end

  def test_goto_works
    skip '需設定 CBETA_XML 指向 cbeta-xml-p5a，或改用 rake remote:test' if XML.nil?

    old = nil
    Dir["#{XML}/**/*.xml"].each do |f|
      bn = File.basename(f, '.*')
      work = CBETA.get_work_id_from_file_basename(bn)
      canon = CBETA.get_canon_id_from_work_id(work)
      unless work == old
        w = work.delete_prefix(canon).sub(/^0*/, '')
        r = get_json(@url, canon:, work: w)
        msg = "Goto 錯誤: url: #{@url}, canon: #{canon}, work: #{w}"
        refute_includes(r, 'error', msg)
      end
    end
  end
  
  def test_goto_linehead
    test_data = [
      'Y01n0001_p0001a01',  
      'T06n0220_p0751c02',  # T0220 跨冊，經號較特別，行首資訊不能變成 T06n0220b
      'T19n1005Ap0624a11',  # 測試 經號後有 A 的情況
      'J36, no. B348, p. 319b5-c12',  # 嘉興藏的經號較特別，有 A 或 B 開頭
      'CBETA 2020.Q1, ZW12, no. a071, p. b8a5',  # 頁碼 英文字母 開頭  
      # 常見引用格式
      'T19, no. 1005A, p. 624a11',
      'B23, no. 130, p. 432a18-24',
      'CBETA, J36, no. B348, p. 319b5-c12',
      'CBETA, Y31, no. 30, p. 163a12-15',
      'DA18',
      'SA498'
    ]

    test_data.each do |linehead|
      params = { linehead: linehead}
      r = get_json(@url, params)
      assert_includes(r, 'num_found')
      assert_operator(r['num_found'], :>, 0)
    end
  end
end
