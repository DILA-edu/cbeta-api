class CbetaString
  HALF_PUNCS = "()*.[]"

  # 全形標點 按內碼順序排列
  FULL_PUNCS = '—…‧─│┬▆◎　、。〃〈〉《》「」『』【】〔〕〖〗︰！（）＊＋，－．／：；＜＝＞？［］～'

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
  end

  def remove_puncs(s)
    s.gsub(@regexp, '')
  end
end
