# frozen_string_literal: true

module Mcp
  # MCP tool wrapping +POST /v1/tools/expand_synonyms+ (near-synonym /
  # 近義詞 expansion).
  class ExpandSynonymsTool < ToolBase
    def name
      'expand_synonyms'
    end

    def description
      <<~DESC.strip
        Return near-synonym (近義詞) expansions for the given term, drawn from
        the CBETA synonym table.

        回傳查詢詞的近義詞列表 (來自 CBETA 同義詞表)。
      DESC
    end

    private

    def controller_class
      V1::ToolsController
    end

    def summarize(data)
      num_found = data['num_found']
      results = data['results'] || []
      lines = ["近義詞: 共 #{num_found} 個。"]
      results.first(30).each { |s| lines << "- #{s}" }
      lines.join("\n")
    end
  end
end
