# frozen_string_literal: true

module Mcp
  # MCP tool wrapping +POST /v1/tools/search_similar+ (semantic / fuzzy
  # similar-passage search using Smith-Waterman alignment).
  class SearchSimilarTool < ToolBase
    def name
      'search_similar'
    end

    def description
      <<~DESC.strip
        Find CBETA passages semantically similar to a short query (recommended
        6–50 characters) using Smith-Waterman alignment. Useful for locating
        paraphrased or partially-quoted passages that exact-match search misses.
        Supports the same filter scope as full-text search (canon, category,
        creator, dynasty, time, work, work_type).

        搜尋與查詢字串語意相近的段落 (建議 6–50 字),適合找出改寫、部份引用、
        或文字略有差異的相似段落。支援與全文檢索相同的範圍過濾 (藏經、部類、
        作譯者、朝代、時間、佛典、佛典類型)。
      DESC
    end

    private

    def controller_class
      V1::ToolsController
    end

    def summarize(data)
      num_found = data['num_found']
      query = data['query_string']
      results = data['results'] || []
      lines = ["近似搜尋「#{query}」: 找到 #{num_found} 筆。"]
      results.first(10).each do |r|
        lines << "- [#{r['canon']}] #{r['title']} 卷#{r['juan']} score=#{r['score']}"
      end
      lines.join("\n")
    end
  end
end
