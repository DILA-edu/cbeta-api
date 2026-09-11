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

  # 全藏約 4900 部典籍，每部各打一次 request 要跑近 5 分鐘，佔整套測試 99% 的
  # request。預設改為分層抽樣：每個藏經抽 GOTO_SAMPLE 部（不足則全取），
  # 26 個藏經共約 360 次。設 CBETA_GOTO_SAMPLE=0 可回到全掃（release 前建議跑）。
  GOTO_SAMPLE = ENV.fetch('CBETA_GOTO_SAMPLE', 20).to_i

  def test_goto_works
    skip '需設定 CBETA_XML 指向 cbeta-xml-p5a，或改用 rake remote:test' if XML.nil?

    works_by_canon.each do |canon, works|
      sample_works(works).each do |work|
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

  private

  # 一部典籍可能拆成多個 XML 檔（分卷），去重後依藏經分組。
  # 分層是必要的: goto 的眉角多半跟藏經有關（ZW 頁碼開頭是英文字母、
  # J 的經號有 A/B 開頭），整體隨機抽樣會讓小藏經幾乎抽不到。
  def works_by_canon
    Dir["#{XML}/**/*.xml"].sort.each_with_object({}) do |f, h|
      work = CBETA.get_work_id_from_file_basename(File.basename(f, '.*'))
      canon = CBETA.get_canon_id_from_work_id(work)
      (h[canon] ||= []) << work
    end.transform_values(&:uniq)
  end

  # 用 Minitest.seed 自建 Random，不用全域的: test 執行順序是隨機的，
  # 全域 RNG 走到這裡的狀態每次都不同，同一個 seed 也會抽到不同典籍，失敗就無法重現。
  def sample_works(works)
    return works if GOTO_SAMPLE <= 0 || works.size <= GOTO_SAMPLE

    works.sample(GOTO_SAMPLE, random: Random.new(Minitest.seed))
  end
end
