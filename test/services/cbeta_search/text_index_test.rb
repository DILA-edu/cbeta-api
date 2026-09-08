require 'test_helper'

class CbetaSearch::TextIndexTest < ActiveSupport::TestCase
  # 連續的拉丁字母/數字算一個 token, 其他每個非空白字元各一個 token。
  # 這個數字是 ElasticQueryBuilder#scored_phrase 的除數, 算錯 term_hits 就會錯。
  test 'token_count: 中文逐字' do
    assert_equal 2, CbetaSearch::TextIndex.token_count('法鼓')
    assert_equal 4, CbetaSearch::TextIndex.token_count('法鼓迦葉')
  end

  test 'token_count: 連續的拉丁字母算一個' do
    assert_equal 1, CbetaSearch::TextIndex.token_count('Ānanda')
    assert_equal 3, CbetaSearch::TextIndex.token_count('Pāli Text Society')
    assert_equal 1, CbetaSearch::TextIndex.token_count('nantanāvāptiśāsani')
  end

  test 'token_count: 中外文混合' do
    assert_equal 4, CbetaSearch::TextIndex.token_count('難陀Śikṣānanda在')
  end

  test 'token_count: 數字算一個 token' do
    assert_equal 4, CbetaSearch::TextIndex.token_count('西元704年')
  end

  test 'token_count: 半形空白不算 token' do
    assert_equal 2, CbetaSearch::TextIndex.token_count('法 鼓')
  end

  test 'token_count: 缺字方塊與 PUA 缺字各算一個 token' do
    # □ (U+25A1) 與 ▆ (U+2586) 在 CBETA 是有意義的正文字元, 不可被丟棄
    assert_equal 3, CbetaSearch::TextIndex.token_count('有□▆')
    assert_equal 2, CbetaSearch::TextIndex.token_count("缺\u{E000}")
  end

  test 'index mapping: content 不存進 _source' do
    body = CbetaSearch::TextIndex.new.index_body

    assert_equal %w[content content_without_notes], body[:mappings][:_source][:excludes]
  end

  test 'index mapping: content 掛 term_freq scripted similarity' do
    body = CbetaSearch::TextIndex.new.index_body
    similarity = body[:settings][:similarity][CbetaSearch::TextIndex::TERM_FREQ_SIMILARITY]

    assert_equal 'scripted', similarity[:type]
    assert_equal CbetaSearch::TextIndex::TERM_FREQ_SCRIPT, similarity[:script][:source]
    assert_equal CbetaSearch::TextIndex::TERM_FREQ_SIMILARITY,
                 body[:mappings][:properties][:content][:similarity]
  end

  test 'index mapping: start 參數上限要大於舊 API 允許的 99999' do
    body = CbetaSearch::TextIndex.new.index_body

    assert_operator body[:settings]['index.max_result_window'], :>, 99_999
  end

  # TOKEN_PATTERN (Elasticsearch 用) 與 TOKEN_RE (Ruby 用) 是兩份實作,
  # 這裡拿實際 index 的 _analyze 輸出比對, 避免兩邊走偏。
  test 'Ruby 與 Elasticsearch 的 token 切分一致' do
    index = CbetaSearch::TextIndex.new
    samples = [
      '法鼓', '阿含', 'Pāli Text Society', 'Ānanda', '難陀Śikṣānanda在',
      '西元704年', '有□▆字', "缺\u{E000}字", '⾔言', "\u{2F8BB}捨",
      "samantato 'nantanāvāptiśāsani", 'Your "mang-kun"'
    ]

    samples.each do |text|
      begin
        tokens = index.analyze(text).fetch('tokens')
      rescue StandardError => e
        skip "Elasticsearch 不可用或 index 不存在: #{e.message}"
      end

      assert_equal CbetaSearch::TextIndex.token_count(text), tokens.size,
                   "token 數不一致: #{text.inspect} -> #{tokens.map { it['token'] }.inspect}"
    end
  end
end
