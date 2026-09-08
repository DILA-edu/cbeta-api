module CbetaSearch
  # 解析後的查詢。
  #
  # type:
  #   :phrase  單一詞組
  #   :near    "A" NEAR/n "B" [NEAR/m "C" ...]
  #   :exclude "A" -"XA" / "A" -"AX"
  #   :bool    AND / OR / NOT 組合
  Query = Struct.new(
    :type,
    :raw,             # 原始查詢字串 (回傳 query_string 用)
    :phrase,          # :phrase / :exclude 的主要詞組
    :near_terms,      # :near 的各詞，依出現順序
    :near_distances,  # :near 的各段距離，長度為 near_terms.size - 1
    :exclude_prefix,  # :exclude 排除前搭配時，被排除字串的前綴
    :exclude_suffix,  # :exclude 排除後搭配時，被排除字串的後綴
    :must,            # :bool 必須出現的詞組
    :should_groups,   # :bool 的 OR 群組; 群組間為 AND、群組內為 OR
    :must_not,        # :bool 不可出現的詞組
    keyword_init: true
  ) do
    # 此查詢的 term_hits 能否直接由 Elasticsearch 的 _score 還原。
    # NEAR 與 Exclude 走 intervals，_score 不是出現次數，必須由 KwicService 逐卷計數。
    def es_countable?
      type == :phrase || type == :bool
    end

    # :bool 查詢中，會貢獻 term_hits 的詞組 (must_not 不計分，與 Manticore 一致)。
    def scoring_terms
      case type
      when :phrase  then [phrase]
      when :bool    then must + should_groups.flatten
      when :exclude then [phrase]
      when :near    then near_terms
      else []
      end
    end
  end
end
