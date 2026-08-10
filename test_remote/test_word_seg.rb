class WordSegTest < Minitest::Test
  def test_word_seg
    url = 'word_seg2'
    r = get_json(url, payload: '佛典自動分詞')
    assert_includes(r, 'segmented', "自動分詞錯誤")
  end
end
