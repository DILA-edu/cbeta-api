# frozen_string_literal: true

module Mcp
  # MCP tool wrapping +POST /v1/tools/find_passages+ (full-text passage search).
  class FindPassagesTool < ToolBase
    def name
      'find_passages'
    end

    # Override the openapi.json description with a richer prompt aimed at
    # LLM clients.
    def description
      <<~DESC.strip
        Search the CBETA Buddhist canon full text and return matching passages
        with surrounding KWIC context. Use the official extended query grammar
        (AND = space-separated quoted terms, OR = |, NOT = !, NEAR = NEAR/n).

        在 CBETA 佛典全文中搜尋詞彙,回傳符合的卷次與前後文 (KWIC)。
        查詢語法:AND 用空白分隔的引號詞、OR 用 |、NOT 用 !、NEAR 用 NEAR/n。
      DESC
    end

    private

    def controller_class
      V1::ToolsController
    end

    def summarize(data)
      num_found = data['num_found']
      total_hits = data['total_term_hits']
      query = data['query_string']
      results = data['results'] || []

      lines = ["查詢「#{query}」:找到 #{num_found} 卷,總命中 #{total_hits} 次。"]
      results.each do |r|
        lines << "- [#{r['canon']}] #{r['title']} 卷#{r['juan']} (#{r['term_hits']} 次)"
      end
      lines.join("\n")
    end
  end
end
