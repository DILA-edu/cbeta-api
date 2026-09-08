module CbetaSearch
  # 把 API 的 q 參數解析成 Query。
  #
  # 支援的語法 (見 app/views/static_pages/search_extended.haml 與 _search-aio-q.haml)：
  #   1. AND       "法鼓" "聖嚴"
  #   2. OR        "波羅蜜" | "波羅密"
  #   3. NOT       "迦葉" !"迦葉佛"
  #   4. NEAR      "法鼓" NEAR/7 "迦葉"
  #   5. NEAR 多詞 "老子" NEAR/7 "道" NEAR/3 "經"
  #   6. Exclude   "直心" -"正直心" / "舍利" -"舍利弗"
  #   7. escape    \" \' \-
  #
  # 不含雙引號的 q 一律視為單一詞組 (含半形空格)，例如 Pāli Text Society，
  # 與舊 all_in_one 的行為一致。
  #
  # 括號分組與 ~n (proximity) 不支援，遇到回 400。
  class QueryParser
    # escape 用的 sentinel: 解析期間先把 \" \' \- 換成 CBETA 原文不會出現的字元
    # (U+FFF9..U+FFFB, interlinear annotation)，避免被當成語法符號，組完再還原。
    ESCAPES = { '\\"' => "￹", "\\'" => "￺", '\\-' => "￻" }.freeze
    UNESCAPES = { "￹" => '"', "￺" => "'", "￻" => '-' }.freeze

    UNSUPPORTED = /[()~&]/

    def parse(raw_query)
      raw = raw_query.to_s.strip
      raise CbetaError.new(400), '缺少 q 參數' if raw.empty?

      masked = mask_escapes(raw)

      # 不含雙引號 → 整串就是一個詞組 (保留空格)
      return build_phrase(raw, masked) unless masked.include?('"')

      check_unsupported!(raw, masked)
      tokens = tokenize(masked, raw)

      return parse_near(raw, tokens) if tokens.any? { |t| t[:type] == :near }
      return parse_exclude(raw, tokens) if exclude?(tokens)

      parse_bool(raw, tokens)
    end

    private

    def mask_escapes(s)
      ESCAPES.reduce(s) { |acc, (from, to)| acc.gsub(from, to) }
    end

    def unmask(s)
      UNESCAPES.reduce(s) { |acc, (from, to)| acc.gsub(from, to) }
    end

    def normalize(term)
      unmask(term).downcase
    end

    def build_phrase(raw, masked)
      phrase = normalize(masked)
      raise CbetaError.new(400), 'q 參數不能是空的' if phrase.empty?

      Query.new(type: :phrase, raw:, phrase:)
    end

    # 括號分組與 ~n 不支援 (見 class 註解)。
    # & 是 Manticore 的 AND 運算子，本專案未對外承諾，一律回 400。
    def check_unsupported!(raw, masked)
      return unless masked.match?(UNSUPPORTED)

      raise CbetaError.new(400),
            "不支援的查詢語法：#{raw}。支援的語法見 /static_pages/search_extended"
    end

    # 把查詢字串切成 token: {type: :term/:or/:not/:exclude/:near, ...}
    def tokenize(masked, raw)
      tokens = []
      rest = masked.dup

      until rest.empty?
        matched =
          if (m = rest.match(/\A\s+/))                          then rest = m.post_match
                                                                     true
          elsif (m = rest.match(/\A\|/))                        then tokens << { type: :or }
                                                                     rest = m.post_match
          elsif (m = rest.match(%r{\ANEAR/(\d+)(?=\s|\z)}))     then tokens << { type: :near, distance: m[1].to_i }
                                                                     rest = m.post_match
          elsif (m = rest.match(/\A!\s*"([^"]*)"/))             then tokens << { type: :not, term: normalize(m[1]) }
                                                                     rest = m.post_match
          elsif (m = rest.match(/\A-\s*"([^"]*)"/))             then tokens << { type: :exclude, term: normalize(m[1]) }
                                                                     rest = m.post_match
          elsif (m = rest.match(/\A"([^"]*)"/))                 then tokens << { type: :term, term: normalize(m[1]) }
                                                                     rest = m.post_match
          elsif (m = rest.match(/\A(\S+)/))                     then # 落到這裡表示引號未配對，去掉引號當一般查詢詞
                                                                     tokens << { type: :term, term: normalize(m[1].delete('"')) }
                                                                     rest = m.post_match
          end
        raise CbetaError.new(400), "無法解析的查詢字串：#{raw}" if matched.nil?
      end

      tokens.reject! { |t| t.key?(:term) && t[:term].empty? }
      raise CbetaError.new(400), "無法解析的查詢字串：#{raw}" if tokens.empty?

      tokens
    end

    def parse_near(raw, tokens)
      terms = []
      distances = []

      tokens.each do |token|
        case token[:type]
        when :term then terms << token[:term]
        when :near then distances << token[:distance]
        else
          raise CbetaError.new(400), "NEAR 不能與其他運算子混用，原查詢字串：#{raw}"
        end
      end

      unless terms.size >= 2 && distances.size == terms.size - 1
        raise CbetaError.new(400), "NEAR 語法錯誤，原查詢字串：#{raw}"
      end

      Query.new(type: :near, raw:, near_terms: terms, near_distances: distances)
    end

    def exclude?(tokens)
      tokens.size == 2 && tokens[0][:type] == :term && tokens[1][:type] == :exclude
    end

    # "A" -"XA" 排除前搭配、"A" -"AX" 排除後搭配。
    # 被排除的字串必須包含原詞組，與舊 all_in_one / KwicService 的語意一致。
    def parse_exclude(raw, tokens)
      phrase = tokens[0][:term]
      excluded = tokens[1][:term]

      if excluded.end_with?(phrase) && excluded != phrase
        Query.new(type: :exclude, raw:, phrase:, exclude_prefix: excluded.delete_suffix(phrase))
      elsif excluded.start_with?(phrase) && excluded != phrase
        Query.new(type: :exclude, raw:, phrase:, exclude_suffix: excluded.delete_prefix(phrase))
      else
        raise CbetaError.new(400),
              "語法錯誤，Exclude #{excluded} 應包含原始字串 #{phrase}，原查詢字串：#{raw}"
      end
    end

    # OR 的優先權高於 (空白隱含的) AND，與 Manticore 一致：
    # A B | C 等於 A AND (B OR C)。
    def parse_bool(raw, tokens)
      groups = []
      must_not = []
      pending_or = false

      tokens.each do |token|
        case token[:type]
        when :or
          raise CbetaError.new(400), "OR 運算子位置錯誤，原查詢字串：#{raw}" if groups.empty?

          pending_or = true
        when :not
          must_not << token[:term]
        when :exclude
          # 單獨的 -"…" 只在 "A" -"B" 這個形式有定義
          raise CbetaError.new(400), %(Exclude 只能用於 "A" -"B" 形式，原查詢字串：#{raw})
        when :term
          if pending_or
            groups.last << token[:term]
            pending_or = false
          else
            groups << [token[:term]]
          end
        end
      end

      raise CbetaError.new(400), "OR 運算子後缺少查詢詞，原查詢字串：#{raw}" if pending_or
      raise CbetaError.new(400), "查詢字串只有排除條件，原查詢字串：#{raw}" if groups.empty?

      must, should_groups = groups.partition { |g| g.size == 1 }
      must.flatten!

      # 單一詞組且無其他條件 → 退回 phrase，走 term_freq 快速路徑
      if must.size == 1 && should_groups.empty? && must_not.empty?
        return Query.new(type: :phrase, raw:, phrase: must.first)
      end

      Query.new(type: :bool, raw:, must:, should_groups:, must_not:)
    end
  end
end
