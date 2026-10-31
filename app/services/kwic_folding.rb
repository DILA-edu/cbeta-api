# KWIC suffix array 的比對正規化：小寫 + 拉丁字母變音符號折疊 (ā → a)。
#
# Elasticsearch 的 analyzer 有 asciifolding (見 CbetaSearch::IndexBase)，
# 搜 Pali Text 會篩出寫成 Pāli Text 的卷；KWIC 若精確比對就找不到，
# 造成 num_found 有數字、results 卻是空的。建檔 (kwic:h2t) 與查詢
# (KwicService) 都必須套用同一個 normalize。
#
# 必須逐字元 1 對 1: suffix array 的每個位置對應 info.dat 裡的一筆
# offset_in_text_with_punc，字元數一變就會錯位。因此只折疊「NFD 後是
# 一個 ASCII 字母 + 組合符號」的預組字元；æ、ß 這類要變成兩個字母的，
# 以及原文本來就是「字母 + 組合符號」(如 N̄) 的序列，都保持原樣。
# NFD 拆不開、但 ASCIIFoldingFilter 對應到單一字母的 (ø → o、ł → l 等)，
# 另列在 EXTRA_FOLD。
# 顯示用的含標點文字另外存放，不受影響。
module KwicFolding
  LATIN_RANGES = [ 0x00C0..0x024F, 0x1E00..0x1EFF ].freeze

  # NFD 拆不開的字母 (已是小寫, normalize 先 downcase)，對應同 Lucene ASCIIFoldingFilter
  EXTRA_FOLD = {
    'ð' => 'd', 'đ' => 'd', 'ħ' => 'h', 'ı' => 'i', 'ĸ' => 'q', 'ŀ' => 'l',
    'ł' => 'l', 'ŋ' => 'n', 'ø' => 'o', 'ŧ' => 't', 'ƀ' => 'b'
  }.freeze

  FOLD = LATIN_RANGES.flat_map(&:to_a).each_with_object({}) do |cp, h|
    c = cp.chr(Encoding::UTF_8)
    base, *marks = c.unicode_normalize(:nfd).chars
    h[c] = base if base.ascii_only? && marks.any? && marks.all?(/\p{Mn}/)
  end.merge(EXTRA_FOLD).freeze

  PATTERN = /[#{FOLD.keys.join}]/

  module_function

  # İ 是唯一 downcase 後會變成兩個字元 (i + U+0307) 的字, 先換掉才能維持 1 對 1
  def normalize(str)
    str.tr('İ', 'I').downcase.gsub(PATTERN, FOLD)
  end
end
