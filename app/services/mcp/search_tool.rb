# frozen_string_literal: true

module Mcp
  # MCP tool wrapping +POST /v1/tools/search+ (platform-friendly search surface).
  #
  # Returns normalized result items (id = linehead, title, url, metadata) suited
  # for a search-then-fetch workflow. Pass the returned +id+ to the +fetch+ tool
  # to retrieve grounded passage text and citation metadata.
  class SearchTool < ToolBase
    def name
      'search'
    end

    def description
      <<~DESC.strip
        Search the CBETA Buddhist canon and return normalized result items.
        Each item has an +id+ (CBETA linehead), +title+, +url+, and +metadata+
        (canon, work, juan, kwic snippet). Pass the +id+ to the +fetch+ tool to
        retrieve the full passage text. Accepts the same scope filters as
        find_passages (canon, category, creator, dynasty, time, work, work_type).

        搜尋 CBETA 佛典全文,回傳正規化結果清單。每筆結果含 id (行首資訊)、
        title、url 與 metadata (藏經、佛典、卷次、KWIC 片段)。
        可將 id 傳給 fetch 工具以取得完整段落文字與引用資訊。
      DESC
    end

    private

    def controller_class
      V1::ToolsController
    end

    def summarize(data)
      results = data['results'] || []
      return '未找到符合的結果。' if results.empty?

      lines = ["共找到 #{results.size} 筆結果:"]
      results.first(5).each do |r|
        meta = r['metadata'] || {}
        lines << "- #{r['id']}  #{r['title']} 卷#{meta['juan']}  #{meta['kwic'].to_s.slice(0, 60)}"
      end
      lines << "…(共 #{results.size} 筆)" if results.size > 5
      lines.join("\n")
    end
  end
end
