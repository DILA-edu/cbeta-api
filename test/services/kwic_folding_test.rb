require 'test_helper'

# KWIC 的比對正規化必須與 Elasticsearch 的 lowercase + asciifolding 一致，
# 且逐字元 1 對 1 (suffix array 的位置要對得上 info.dat)。
class KwicFoldingTest < ActiveSupport::TestCase
  test '小寫並折疊變音符號' do
    assert_equal 'pali text', KwicFolding.normalize('Pāli Text')
    assert_equal 'thana sri nana', KwicFolding.normalize('Ṭhāna ŚRĪ ñāṇa')
  end

  test '不能 1 對 1 折疊的字元保持原樣' do
    assert_equal 'æ ß', KwicFolding.normalize('æ ß')
    assert_equal 'n̄', KwicFolding.normalize('N̄') # 字母 + 組合符號
  end

  # NFD 拆不開, 但 Elasticsearch 的 asciifolding 會折成單一字母
  test '折疊 NFD 拆不開的字母' do
    assert_equal 'soren lodz d h i', KwicFolding.normalize('Søren Łódź Đ ħ ı')
  end

  # İ downcase 後會變成 i + U+0307 兩個字元, 之後的 offset 會整個錯開
  test 'İ 折成 i, 字元數不變' do
    assert_equal 'istanbul', KwicFolding.normalize('İstanbul')
  end

  test 'CJK 不受影響' do
    assert_equal '阿含經', KwicFolding.normalize('阿含經')
  end

  test '字元數不變' do
    s = 'Pāli Text Ṭhāna æ ß N̄ 阿含 ñāṇa İ Ø Ł'
    assert_equal s.size, KwicFolding.normalize(s).size
  end
end
