# frozen_string_literal: true

module Mcp
  # JSON-RPC level error raised during MCP message dispatch. The +code+ maps to
  # a JSON-RPC error code (see https://www.jsonrpc.org/specification#error_object).
  class Error < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end
end
