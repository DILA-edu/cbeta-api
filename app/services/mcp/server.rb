# frozen_string_literal: true

module Mcp
  # Minimal MCP (Model Context Protocol) server implementing the JSON-RPC 2.0
  # message dispatch used by the Streamable HTTP transport.
  #
  # This class is transport-agnostic: it takes an already-parsed JSON-RPC
  # message (a Hash, or an Array for a batch) and returns the Ruby Hash/Array to
  # be serialized back as the response, or +nil+ when the input contains only
  # notifications/responses (the transport should then reply 202 Accepted).
  #
  # Tools are plain objects responding to +name+, +description+, +input_schema+
  # and +call(arguments)+ (see Mcp::FindPassagesTool).
  class Server
    SERVER_INFO = { name: 'cbeta-mcp', version: '0.1.0' }.freeze

    # Protocol versions we understand, newest first. We echo back the client's
    # requested version when supported, otherwise fall back to the newest.
    SUPPORTED_PROTOCOL_VERSIONS = %w[2025-06-18 2025-03-26 2024-11-05].freeze
    DEFAULT_PROTOCOL_VERSION = SUPPORTED_PROTOCOL_VERSIONS.first

    def initialize(tools:)
      @tools = tools
    end

    # Dispatch a single message or a batch. Returns the response object, an
    # array of responses (for a batch), or nil when there is nothing to send.
    def handle(message)
      if message.is_a?(Array)
        return error_response(nil, -32600, 'Invalid Request: empty batch') if message.empty?

        responses = message.map { |m| handle_one(m) }.compact
        responses.empty? ? nil : responses
      else
        handle_one(message)
      end
    end

    # Response for a body that could not be parsed as JSON.
    def self.parse_error
      { jsonrpc: '2.0', id: nil, error: { code: -32700, message: 'Parse error' } }
    end

    private

    def handle_one(msg)
      return error_response(nil, -32600, 'Invalid Request') unless msg.is_a?(Hash)

      id = msg['id']
      method = msg['method']
      notification = !msg.key?('id')

      # Client-originated notifications (e.g. notifications/initialized) and any
      # incoming responses require no reply.
      return nil if notification

      result =
        case method
        when 'initialize'  then handle_initialize(msg['params'])
        when 'ping'        then {}
        when 'tools/list'  then handle_tools_list
        when 'tools/call'  then handle_tools_call(msg['params'])
        else
          return error_response(id, -32601, "Method not found: #{method}")
        end

      { jsonrpc: '2.0', id: id, result: result }
    rescue Mcp::Error => e
      error_response(id, e.code, e.message)
    rescue StandardError => e
      Rails.logger.error("[MCP] #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
      error_response(id, -32603, 'Internal error')
    end

    def handle_initialize(params)
      requested = params.is_a?(Hash) ? params['protocolVersion'] : nil
      version =
        SUPPORTED_PROTOCOL_VERSIONS.include?(requested) ? requested : DEFAULT_PROTOCOL_VERSION

      {
        protocolVersion: version,
        capabilities: { tools: { listChanged: false } },
        serverInfo: SERVER_INFO
      }
    end

    def handle_tools_list
      {
        tools: @tools.map do |t|
          { name: t.name, description: t.description, inputSchema: t.input_schema }
        end
      }
    end

    def handle_tools_call(params)
      raise Mcp::Error.new(-32602, 'Invalid params') unless params.is_a?(Hash)

      name = params['name']
      tool = @tools.find { |t| t.name == name }
      raise Mcp::Error.new(-32602, "Unknown tool: #{name.inspect}") if tool.nil?

      arguments = params['arguments'] || {}
      raise Mcp::Error.new(-32602, 'arguments must be an object') unless arguments.is_a?(Hash)

      tool.call(arguments)
    end

    def error_response(id, code, message)
      { jsonrpc: '2.0', id: id, error: { code: code, message: message } }
    end
  end
end
