# frozen_string_literal: true

module Mcp
  # MCP tool wrapping +POST /v1/tools/search_notes+ (annotations and collation
  # notes / 校勘記 full-text search).
  class SearchNotesTool < ToolBase
    def name
      'search_notes'
    end

    def description
      <<~DESC.strip
        Search CBETA annotations and collation notes (注釋與校勘記) by full text.

        搜尋 CBETA 注釋與校勘記。
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

      lines = ["查詢「#{query}」: 找到 #{num_found} 筆注釋/校勘記。"]
      results.first(20).each do |r|
        lines << "- [#{r['canon']}] #{r['title']} 卷#{r['juan']} #{r['lb']} (#{r['note_place']})"
      end
      lines.join("\n")
    end
  end
end
