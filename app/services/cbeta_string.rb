class CbetaString
  HALF_PUNCS = "()*.[]"

  # 全形標點 按內碼順序排列
  # 2025-07-24 CBETA 決議 把「□」和「▆」當作一般文字，不忽略。
  #   * “□” (U+25A1) 表示此處應該有字，但編書的人也不知道是什麼字，就印出一個空白方塊「□」。
  #   * XML unclear 元素 轉成各版用字會使用 “▆” (U+2586) 字元，
  #     這是 CBETA 認為書中文字難以辨識，例如影印古籍，但此處有污損或蟲蛀。
  FULL_PUNCS = '—…‧─│┬△◎　、。〃〈〉《》「」『』【】〔〕〖〗︰！（）＊＋，－．／：；＜＝＞？［］～'
  
  PUNCS = HALF_PUNCS + FULL_PUNCS

  def initialize(allow_digit: false, allow_space: true, allow_comma: false)
    s = PUNCS
    s = Regexp.quote(s)
    s << '\n'
    s << '\d' unless allow_digit

    # kwic query 語法 允許 半形逗點
    s << ','  unless allow_comma

    # 預設 保留 半形空格，否則會搜不到：Pāli Text Society
    s << ' ' unless allow_space

    @regexp = /[#{s}]/
    @regexp2 = /[#{s}]\z/
  end

  def end_with_puncs?(s)
    s.match?(@regexp2)
  end

  def remove_puncs(s)
    s.gsub(@regexp, '')
  end
end
