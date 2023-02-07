class CbetaString
  HALF_PUNCS = "()*,.[]"

  # 全形標點 按內碼順序排列
  FULL_PUNCS = '—…‧─│┬▆◎　、。〃〈〉《》「」『』【】〔〕〖〗︰！（）＊＋，－．／：；＜＝＞？［］～'

  PUNCS = HALF_PUNCS + FULL_PUNCS

  def initialize(allow_digit: false, allow_space: true)
    s = PUNCS
    s = Regexp.quote(s)
    s << '\n'
    s << '\d' unless allow_digit

    # 預設 保留 半形空格，否則會搜不到：Pāli Text Society
    s << ' ' unless allow_space

    @regexp = /[#{s}]/
  end

  def remove_puncs(s)
    s.gsub(@regexp, '')
  end
end
