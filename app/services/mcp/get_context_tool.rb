# frozen_string_literal: true

module Mcp
  # MCP tool wrapping +POST /v1/tools/get_context+ (return surrounding text
  # lines for a linehead anchor or range).
  class GetContextTool < ToolBase
    def name
      'get_context'
    end

    def description
      <<~DESC.strip
        Return surrounding text lines for a CBETA linehead anchor, or for a
        linehead_start/linehead_end range. Each result includes the rendered
        HTML for the line and any associated footnote text.

        傳回 CBETA 行首資訊前後的文字行,或指定行首資訊範圍內的文字。
        每筆結果包含該行的 HTML 與相關註解文字。
      DESC
    end

    private

    def controller_class
      V1::ContextsController
    end

    def controller_action
      :get_context
    end

    def summarize(data)
      num_found = data['num_found']
      results = data['results'] || []
      lines = ["取得 #{num_found} 行內文。"]
      results.first(5).each { |r| lines << "- #{r['linehead']}" }
      lines << "…" if results.size > 5
      lines.join("\n")
    end
  end
end
