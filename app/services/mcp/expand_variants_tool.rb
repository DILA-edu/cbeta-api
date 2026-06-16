# frozen_string_literal: true

module Mcp
  # MCP tool wrapping +POST /v1/tools/expand_variants+ (glyph variants /
  # 異體字 expansion).
  class ExpandVariantsTool < ToolBase
    def name
      'expand_variants'
    end

    def description
      <<~DESC.strip
        Return glyph variants (異體字) for the given query, plus the hit count
        for each variant in the CBETA corpus. Useful for broadening a search
        to cover historical character variants.

        回傳查詢詞的異體字組合,以及各組合在 CBETA 中的命中數,用於擴展查詢。
      DESC
    end

    private

    def controller_class
      V1::ToolsController
    end

    def summarize(data)
      num_found = data['num_found']
      possibility = data['possibility']
      results = data['results'] || []
      lines = ["異體字展開: #{possibility} 組合,#{num_found} 組有命中。"]
      results.first(20).each do |r|
        lines << "- #{r['q']} (#{r['hits']} 次)"
      end
      lines.join("\n")
    end
  end
end
