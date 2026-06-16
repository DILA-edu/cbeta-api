# frozen_string_literal: true

require 'test_helper'

module Mcp
  # Unit tests for the schema-loading and result-building behaviour of
  # Mcp::ToolBase. These tests stub out the in-process dispatch so they don't
  # depend on the search backend.
  class ToolBaseTest < ActiveSupport::TestCase
    # Concrete subclass that points at a real openapi path
    # (/v1/tools/find_passages) so we can exercise schema loading without
    # mocking the openapi.json document.
    class StubTool < Mcp::ToolBase
      def name
        'find_passages'
      end

      attr_writer :stub_body

      private

      def controller_class
        Object # not used; dispatch is stubbed
      end

      def dispatch(_arguments)
        @stub_body
      end
    end

    def setup
      @tool = StubTool.new
    end

    test 'input_schema is loaded from public/openapi.json' do
      schema = @tool.input_schema
      assert_equal 'object', schema['type']
      assert_includes schema['required'], 'q'
      assert schema.dig('properties', 'q'), 'expected q property'
    end

    test 'output_schema is loaded from openapi response.200 data schema' do
      schema = @tool.output_schema
      assert_equal 'object', schema['type']
      assert schema.dig('properties', 'results'), 'expected results property'
    end

    test 'description falls back to openapi description' do
      # StubTool doesn't override description, so it should come from openapi.
      assert_match(/CBETA/, @tool.description)
    end

    test 'call wraps a successful tool envelope as MCP content + structuredContent' do
      payload = {
        ok: true,
        tool: 'find_passages',
        request_id: 'rid',
        data: { 'num_found' => 1, 'results' => [] }
      }
      @tool.stub_body = JSON.generate(payload)

      result = @tool.call({})
      refute result[:isError]
      assert_equal({ 'num_found' => 1, 'results' => [] }, result[:structuredContent])
      assert_kind_of Array, result[:content]
      assert_equal 2, result[:content].size # summary + raw JSON
      assert_equal 'text', result[:content].first[:type]
    end

    test 'call wraps a 4xx tool envelope as isError=true' do
      payload = {
        ok: false,
        tool: 'find_passages',
        request_id: 'rid',
        error_code: 'invalid_request',
        message: 'Missing required parameter: q',
        retryable: false
      }
      @tool.stub_body = JSON.generate(payload)

      result = @tool.call({})
      assert result[:isError]
      assert_equal 'Missing required parameter: q', result[:content].first[:text]
      # The full envelope is preserved as structuredContent for inspection.
      assert_equal 'invalid_request', result[:structuredContent]['error_code']
    end

    test 'call handles non-JSON dispatch output gracefully' do
      @tool.stub_body = '<html>broken</html>'
      result = @tool.call({})
      assert result[:isError]
      assert_match(/無法解析/, result[:content].first[:text])
    end

    test 'call rescues exceptions raised during dispatch' do
      # Override dispatch via singleton method.
      def @tool.dispatch(_arguments) = raise StandardError, 'boom'

      result = @tool.call({})
      assert result[:isError]
      assert_match(/find_passages 執行失敗/, result[:content].first[:text])
    end
  end
end
