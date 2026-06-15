# frozen_string_literal: true

require 'test_helper'

module Mcp
  class ServerTest < ActiveSupport::TestCase
    # Minimal stand-in tool so dispatch can be tested without any network I/O.
    class FakeTool
      def name = 'fake'
      def description = 'a fake tool'
      def input_schema = { type: 'object', properties: {} }

      def call(arguments)
        {
          content: [{ type: 'text', text: "got #{arguments['x']}" }],
          structuredContent: { 'echo' => arguments['x'] },
          isError: false
        }
      end
    end

    def setup
      @server = Mcp::Server.new(tools: [FakeTool.new])
    end

    test 'initialize echoes a supported protocol version and advertises tools' do
      res = @server.handle('jsonrpc' => '2.0', 'id' => 1, 'method' => 'initialize',
                           'params' => { 'protocolVersion' => '2025-06-18' })

      assert_equal '2.0', res[:jsonrpc]
      assert_equal 1, res[:id]
      assert_equal '2025-06-18', res[:result][:protocolVersion]
      assert res[:result][:capabilities][:tools]
      assert_equal 'cbeta-mcp', res[:result][:serverInfo][:name]
    end

    test 'initialize falls back to default protocol when unsupported' do
      res = @server.handle('id' => 1, 'method' => 'initialize',
                           'params' => { 'protocolVersion' => '1999-01-01' })

      assert_equal Mcp::Server::DEFAULT_PROTOCOL_VERSION, res[:result][:protocolVersion]
    end

    test 'tools/list returns the registered tools' do
      res = @server.handle('id' => 2, 'method' => 'tools/list')
      tools = res[:result][:tools]

      assert_equal 1, tools.size
      assert_equal 'fake', tools.first[:name]
      assert tools.first[:inputSchema]
    end

    test 'ping returns an empty result' do
      res = @server.handle('id' => 3, 'method' => 'ping')
      assert_equal({}, res[:result])
    end

    test 'tools/call dispatches to the named tool' do
      res = @server.handle('id' => 4, 'method' => 'tools/call',
                           'params' => { 'name' => 'fake', 'arguments' => { 'x' => 42 } })

      refute res[:result][:isError]
      assert_equal({ 'echo' => 42 }, res[:result][:structuredContent])
    end

    test 'tools/call with unknown tool is an invalid params error' do
      res = @server.handle('id' => 5, 'method' => 'tools/call',
                           'params' => { 'name' => 'nope' })

      assert_equal(-32602, res[:error][:code])
    end

    test 'unknown method returns method not found' do
      res = @server.handle('id' => 6, 'method' => 'does/not/exist')
      assert_equal(-32601, res[:error][:code])
    end

    test 'notifications produce no response' do
      assert_nil @server.handle('method' => 'notifications/initialized')
    end

    test 'a batch returns an array of responses, dropping notifications' do
      res = @server.handle([
                             { 'id' => 1, 'method' => 'ping' },
                             { 'method' => 'notifications/initialized' },
                             { 'id' => 2, 'method' => 'ping' }
                           ])

      assert_kind_of Array, res
      assert_equal 2, res.size
      assert_equal [1, 2], res.map { |r| r[:id] }
    end

    test 'empty batch is an invalid request' do
      res = @server.handle([])
      assert_equal(-32600, res[:error][:code])
    end
  end
end
