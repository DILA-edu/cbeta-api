# frozen_string_literal: true

require 'rack/mock'
require 'json'

module Mcp
  # Base class for MCP tools that wrap /v1/tools/* HTTP endpoints.
  #
  # Subclasses declare:
  #   * +name+ (and optionally +description+) — what MCP advertises
  #   * +controller_class+ / +controller_action+ — where to dispatch in-process
  #   * +summarize(data)+ — optional human-readable text for clients that only
  #     read the +content+ array
  #
  # Input and output JSON schemas are loaded from public/openapi.json so the
  # MCP advertisement stays in sync with the HTTP contract automatically.
  class ToolBase
    OPENAPI_PATH = Rails.root.join('public', 'openapi.json').freeze

    class << self
      def openapi_doc
        @openapi_doc ||= JSON.parse(File.read(OPENAPI_PATH))
      end
    end

    def name
      raise NotImplementedError
    end

    def description
      openapi_op['description'] || openapi_op['summary'] || ''
    end

    def input_schema
      openapi_op.dig('requestBody', 'content', 'application/json', 'schema') || { 'type' => 'object' }
    end

    def output_schema
      openapi_op.dig('responses', '200', 'content', 'application/json', 'schema', 'properties', 'data') || {}
    end

    def call(arguments)
      build_result(parse_json(dispatch(arguments)))
    rescue StandardError => e
      Rails.logger.error("[MCP] #{name} dispatch failed: #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
      tool_error("#{name} 執行失敗: #{e.message}")
    end

    private

    def controller_class
      raise NotImplementedError
    end

    def controller_action
      name.to_sym
    end

    def path
      "/v1/tools/#{name}"
    end

    def openapi_op
      @openapi_op ||= self.class.openapi_doc.dig('paths', path, 'post') || {}
    end

    def dispatch(arguments)
      env = Rack::MockRequest.env_for(
        path,
        method: 'POST',
        input: JSON.generate(arguments),
        'CONTENT_TYPE' => 'application/json',
        'HTTP_ACCEPT' => 'application/json',
        'HTTP_USER_AGENT' => 'cbeta-mcp'
      )
      _status, _headers, body = controller_class.action(controller_action).call(env)
      read_body(body)
    end

    def read_body(body)
      buffer = +''
      body.each { |chunk| buffer << chunk }
      buffer
    ensure
      body.close if body.respond_to?(:close)
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError, TypeError
      nil
    end

    def build_result(payload)
      return tool_error("#{name} 回傳非預期的內容 (無法解析為 JSON)") if payload.nil?

      if payload['ok']
        data = payload['data'] || {}
        {
          content: [
            { type: 'text', text: summarize(data) },
            { type: 'text', text: JSON.generate(data) }
          ],
          structuredContent: data,
          isError: false
        }
      else
        message = payload['message'] || "#{name} 回報錯誤"
        tool_error(message, structured: payload)
      end
    end

    # Short human-readable header for clients that only read text content.
    # Subclasses are encouraged to override with something tool-specific.
    def summarize(data)
      return data.to_s[0, 200] unless data.is_a?(Hash)
      "num_found: #{data['num_found']}"
    end

    def tool_error(message, structured: nil)
      result = {
        content: [{ type: 'text', text: message }],
        isError: true
      }
      result[:structuredContent] = structured if structured
      result
    end
  end
end
