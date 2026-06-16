# frozen_string_literal: true

module Mcp
  # MCP tool wrapping +POST /v1/tools/fetch+ (grounded passage text by id).
  #
  # Accepts a CBETA linehead +id+ (typically from a +search+ result) and returns
  # the passage text with 3 lines of context on each side, plus citation metadata.
  class FetchTool < ToolBase
    def name
      'fetch'
    end

    def description
      <<~DESC.strip
        Fetch a CBETA passage by id (linehead). Returns grounded plain text
        (3 context lines before and after the anchor line) and citation metadata
        (work, juan, vol, lb, linehead, url). Use after +search+ to retrieve the
        full text for a specific result item.

        依 id (行首資訊) 取得 CBETA 段落文字。回傳以錨點行為中心、前後各 3 行的
        純文字內文,以及引用 metadata (佛典、卷次、冊號、行號、行首資訊、URL)。
        通常在 search 之後使用,用於取得特定結果的完整段落。
      DESC
    end

    private

    def controller_class
      V1::FetchController
    end

    def controller_action
      :fetch
    end

    def summarize(data)
      title    = data['title'].to_s
      id       = data['id'].to_s
      text     = data['text'].to_s.slice(0, 200)
      meta     = data['metadata'] || {}
      line_cnt = meta['line_count']

      lines = ["#{title} (#{id}, #{line_cnt} 行)"]
      lines << text
      lines << "…" if data['text'].to_s.length > 200
      lines.join("\n")
    end
  end
end
