# frozen_string_literal: true

module Mcp
  # MCP tool wrapping +POST /v1/tools/resolve_citation+ (citation -> CBETA
  # location resolver).
  class ResolveCitationTool < ToolBase
    def name
      'resolve_citation'
    end

    def description
      <<~DESC.strip
        Resolve a CBETA citation to a canonical location (canon, work, juan,
        file, linehead). Accepts either a free-text +linehead+ (e.g.
        "T01n0001_p0066c25", "CBETA, T01, no. 1, p. 67, a13",
        "《大正藏》冊19，第974C號，頁386") or structured fields
        (canon + work + page + col + line).

        將 CBETA 引用 (行首資訊或結構化欄位) 解析為標準位置 (藏經、佛典、卷、
        檔名、行首資訊)。可傳入 linehead 字串,或 canon + work + page + col + line。
      DESC
    end

    private

    def controller_class
      V1::CitationsController
    end

    def controller_action
      :resolve_citation
    end

    def summarize(data)
      num_found = data['num_found']
      results = data['results'] || []
      return "找不到對應的 CBETA 位置。" if num_found.to_i.zero?
      lines = ["找到 #{num_found} 個位置:"]
      results.each do |r|
        lines << "- #{r['linehead']} (#{r['work']} #{r['title']} 卷#{r['juan']})"
      end
      lines.join("\n")
    end
  end
end
