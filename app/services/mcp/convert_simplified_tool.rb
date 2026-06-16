# frozen_string_literal: true

module Mcp
  # MCP tool wrapping +POST /v1/tools/convert_simplified+ (simplified-to-
  # traditional Chinese conversion, plus full-corpus hit count for the
  # converted term).
  class ConvertSimplifiedTool < ToolBase
    def name
      'convert_simplified'
    end

    def description
      <<~DESC.strip
        Convert simplified Chinese input (簡體) to traditional Chinese (正體)
        and return the number of CBETA hits for the converted form.

        將簡體中文轉為繁體 (正體) 中文,並回傳該繁體字串在 CBETA 中的命中數。
      DESC
    end

    private

    def controller_class
      V1::ToolsController
    end

    def summarize(data)
      "簡轉繁: #{data['q']} (#{data['hits']} 次)"
    end
  end
end
