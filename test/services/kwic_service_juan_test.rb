require 'test_helper'

# 用一小段文字建出單卷的 suffix array 檔 (格式同 kwic:build), 端到端測 KwicService。
class KwicServiceJuanTest < ActiveSupport::TestCase
  PUNCS = '，。'
  # 不含標點: 我實成佛已來其實為佛乘成佛道 (佛 在 3、9、12)
  TEXT_WITH_PUNC = "我實成佛已來，其實為佛乘。成佛道。\0"

  setup do
    @base = Dir.mktmpdir
    @plain = build_juan(@base, TEXT_WITH_PUNC)
  end

  teardown do
    FileUtils.remove_entry(@base)
  end

  # 單卷的 :sa_offset 是 suffix array 的 index, 原本被當成文字 offset 讀
  test 'kwic_no_punc 是命中位置的前後文' do
    r = search_juan('佛', kwic_wo_punc: true, mark: true)

    expected = positions('佛').map do |i|
      s = @plain[[ i - 5, 0 ].max...i] + '<mark>佛</mark>' + @plain[i + 1, 5]
      s.tr("\n", '　')
    end
    assert_equal expected.sort, r[:results].map { it['kwic_no_punc'] }.sort
  end

  # sort=b 讀的是倒序全文, 原本排除字串仍照正序組, 排除錯對象
  test 'sort=b 的 negative_lookbehind / negative_lookahead 與正序結果相同' do
    [ { negative_lookbehind: '成' }, { negative_lookahead: '乘' } ].each do |opt|
      f = search_juan('佛', **opt)
      b = search_juan('佛', sort: 'b', **opt)

      assert_equal 2 - (opt.key?(:negative_lookbehind) ? 1 : 0), f[:num_found], opt.inspect
      assert_equal lbs_and_offsets(f), lbs_and_offsets(b), opt.inspect
    end
  end

  # NEAR 的位置計算都假設正序; sort=b 原本會讀倒序檔, 回傳無關的位置
  test 'NEAR 忽略 sort=b' do
    q = '"佛" NEAR/3 "乘"'
    f = new_service.search_near(q, work: 'T0001', juan: 1)
    b = new_service.search_near(q, work: 'T0001', juan: 1, sort: 'b')

    assert_equal 2, f[:num_found] # 為佛乘、乘。成佛 (NEAR 不分先後)
    assert_equal(f[:results].map { it['kwic'] }, b[:results].map { it['kwic'] })
  end

  # KwicService 原本自己用 regex 重新 parse, 要求恰好一個空格, 與 QueryParser 不一致
  test 'NEAR 的空白規則與 QueryParser 一致' do
    expected = new_service.search_near('"佛" NEAR/3 "乘"', work: 'T0001', juan: 1)[:results]

    [ '"佛"  NEAR/3 "乘"', '"佛" NEAR/3  "乘"', "\"佛\"\tNEAR/3 \"乘\"", '"佛"NEAR/3 "乘"' ].each do |q|
      assert_equal expected, new_service.search_near(q, work: 'T0001', juan: 1)[:results], q
      assert_equal expected.size, new_service.count_near(q, work: 'T0001', juan: 1), q
    end
  end

  # 被略過的重疊詞會覆寫 p2, 原本後文從錯的位置讀, 「已」重複一次
  test 'NEAR 詞彼此包含時不重複輸出文字' do
    r = new_service.search_near('"實" NEAR/5 "成佛已" NEAR/0 "佛"', work: 'T0001', juan: 1)

    assert_includes r[:results].map { it['kwic'] }, '我<mark>實</mark><mark>成佛已</mark>來，其實為'
  end

  private

  def new_service
    KwicService.new(@base, true)
  end

  def search_juan(q, **opts)
    new_service.search_juan(q, { work: 'T0001', juan: 1 }.merge(opts))
  end

  def positions(q)
    (0...@plain.size).select { @plain[it, q.size] == q }
  end

  def lbs_and_offsets(result)
    result[:results].map { it['offset_in_text_with_punc'] }.sort
  end

  # 回傳不含標點的全文
  def build_juan(base, text_with_punc)
    plain = +''
    offsets = []
    text_with_punc.each_char.with_index do |c, i|
      next if PUNCS.include?(c)

      plain << c
      offsets << i
    end

    dir = File.join(base, 'sa', 'T0001', '001')
    FileUtils.mkdir_p(dir)
    [ [ plain, '' ], [ plain.reverse, '-b' ] ].each do |text, suffix|
      sa = (0...text.size).sort_by { text[it..] }
      File.binwrite(File.join(dir, "all#{suffix}.txt"), text.encode('UTF-32LE'))
      File.binwrite(File.join(dir, "sa#{suffix}.dat"), sa.pack('V*'))
    end
    info = offsets.map do |o|
      SuffixInfo.new(vol: 'T01', work: 'T0001', juan: 1, offset_in_text_with_punc: o, lb: 'lb0001a01').pack
    end
    File.binwrite(File.join(dir, 'info.dat'), info.join)

    text_dir = File.join(base, 'text', 'T', 'T0001')
    FileUtils.mkdir_p(text_dir)
    File.binwrite(File.join(text_dir, '001.txt'), text_with_punc.encode('UTF-32LE'))

    plain
  end
end
