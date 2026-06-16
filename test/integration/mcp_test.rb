# frozen_string_literal: true

require 'test_helper'

class McpTest < ActionDispatch::IntegrationTest
  HEADERS = { 'Content-Type' => 'application/json', 'User-Agent' => 'mcp-test' }.freeze

  def post_mcp(payload)
    post '/mcp', params: JSON.generate(payload), headers: HEADERS
  end

  test 'initialize handshake over HTTP' do
    post_mcp(jsonrpc: '2.0', id: 1, method: 'initialize',
             params: { protocolVersion: '2025-06-18' })

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body['id']
    assert_equal 'cbeta-mcp', body.dig('result', 'serverInfo', 'name')
  end

  EXPECTED_TOOL_NAMES = %w[
    find_passages
    search_notes
    expand_variants
    expand_synonyms
    convert_simplified
    search_similar
    resolve_citation
    get_context
  ].freeze

  Q_REQUIRED_TOOLS = %w[
    find_passages
    search_notes
    expand_variants
    expand_synonyms
    convert_simplified
    search_similar
  ].freeze

  test 'tools/list exposes find_passages with input and output schemas' do
    post_mcp(jsonrpc: '2.0', id: 2, method: 'tools/list')

    assert_response :success
    tools = JSON.parse(response.body).dig('result', 'tools')
    names = tools.map { |t| t['name'] }
    assert_includes names, 'find_passages'

    tool = tools.find { |t| t['name'] == 'find_passages' }
    assert_includes tool['inputSchema']['required'], 'q'
    assert_equal 'object', tool.dig('outputSchema', 'type')
    assert tool.dig('outputSchema', 'properties', 'results'), 'outputSchema missing results'
  end

  test 'tools/list exposes all v1 tools' do
    post_mcp(jsonrpc: '2.0', id: 20, method: 'tools/list')
    assert_response :success
    names = JSON.parse(response.body).dig('result', 'tools').map { |t| t['name'] }
    EXPECTED_TOOL_NAMES.each { |n| assert_includes names, n, "tools/list missing #{n}" }
  end

  test 'tools/list advertises q as required on every q-based tool' do
    post_mcp(jsonrpc: '2.0', id: 21, method: 'tools/list')
    tools = JSON.parse(response.body).dig('result', 'tools')
    Q_REQUIRED_TOOLS.each do |name|
      tool = tools.find { |t| t['name'] == name }
      refute_nil tool, "#{name} missing from tools/list"
      assert_includes tool.dig('inputSchema', 'required'), 'q', "#{name} should require q"
      assert_equal 'object', tool.dig('outputSchema', 'type'), "#{name} outputSchema.type should be object"
    end
  end

  test 'tools/list resolve_citation declares structured citation fields' do
    post_mcp(jsonrpc: '2.0', id: 22, method: 'tools/list')
    tool = JSON.parse(response.body).dig('result', 'tools').find { |t| t['name'] == 'resolve_citation' }
    props = tool.dig('inputSchema', 'properties')
    %w[linehead canon work juan page col line].each do |field|
      assert props.key?(field), "resolve_citation inputSchema missing #{field}"
    end
  end

  test 'tools/list get_context declares linehead range fields' do
    post_mcp(jsonrpc: '2.0', id: 23, method: 'tools/list')
    tool = JSON.parse(response.body).dig('result', 'tools').find { |t| t['name'] == 'get_context' }
    props = tool.dig('inputSchema', 'properties')
    %w[linehead linehead_start linehead_end before after].each do |field|
      assert props.key?(field), "get_context inputSchema missing #{field}"
    end
  end

  test 'tools/call dispatches in-process and returns a well-formed result' do
    # Does not assert isError, since that depends on whether the search backend
    # (Manticore) is reachable in the running environment. Asserts the envelope
    # shape only.
    post_mcp(jsonrpc: '2.0', id: 7, method: 'tools/call',
             params: { name: 'find_passages', arguments: { q: '佛', rows: 1 } })

    assert_response :success
    result = JSON.parse(response.body).fetch('result')
    assert_kind_of Array, result['content']
    assert_includes [true, false], result['isError']
  end

  # Each q-required tool should surface the same isError=true result when q is
  # missing — validation happens inside the V1 controller's prepare hook BEFORE
  # any backend call, so this is safe to assert deterministically.
  Q_REQUIRED_TOOLS.each do |name|
    test "tools/call #{name} without q yields isError=true" do
      post_mcp(jsonrpc: '2.0', id: 100, method: 'tools/call',
               params: { name: name, arguments: {} })

      assert_response :success
      result = JSON.parse(response.body).fetch('result')
      assert_equal true, result['isError'], "#{name} should report isError"
      # The full HTTP error envelope is carried through as structuredContent.
      assert_equal false, result.dig('structuredContent', 'ok')
      assert_equal name, result.dig('structuredContent', 'tool')
      assert_equal 'invalid_request', result.dig('structuredContent', 'error_code')
    end
  end

  test 'tools/call resolve_citation without linehead/canon yields isError=true' do
    post_mcp(jsonrpc: '2.0', id: 110, method: 'tools/call',
             params: { name: 'resolve_citation', arguments: {} })

    assert_response :success
    result = JSON.parse(response.body).fetch('result')
    assert_equal true, result['isError']
    assert_equal 'invalid_request', result.dig('structuredContent', 'error_code')
  end

  test 'tools/call get_context without linehead/range yields isError=true' do
    post_mcp(jsonrpc: '2.0', id: 111, method: 'tools/call',
             params: { name: 'get_context', arguments: {} })

    assert_response :success
    result = JSON.parse(response.body).fetch('result')
    assert_equal true, result['isError']
    assert_equal 'invalid_request', result.dig('structuredContent', 'error_code')
  end

  test 'tools/call with unknown tool name yields a JSON-RPC error' do
    post_mcp(jsonrpc: '2.0', id: 120, method: 'tools/call',
             params: { name: 'no_such_tool', arguments: {} })

    body = JSON.parse(response.body)
    # Per MCP, unknown tool names are surfaced as a JSON-RPC error, not as
    # an isError tool result.
    assert_equal(-32602, body.dig('error', 'code'))
  end

  test 'tools/call each tool returns a well-formed result envelope' do
    # Doesn't assert isError per tool, since backend availability varies.
    # Just verifies the dispatch reaches the V1 controller for each tool
    # and produces a content array.
    happy_args = {
      'find_passages'      => { q: '佛', rows: 1 },
      'search_notes'       => { q: '佛', rows: 1 },
      'expand_variants'    => { q: '佛' },
      'expand_synonyms'    => { q: '佛' },
      'convert_simplified' => { q: '佛' },
      'search_similar'     => { q: '一切眾生皆有佛性', k: 1 },
      'resolve_citation'   => { linehead: 'T01n0001_p0001a01' },
      'get_context'        => { linehead: 'T01n0001_p0001a01', before: 0, after: 0 }
    }

    EXPECTED_TOOL_NAMES.each do |name|
      post_mcp(jsonrpc: '2.0', id: 200, method: 'tools/call',
               params: { name: name, arguments: happy_args.fetch(name) })

      assert_response :success, "#{name} HTTP status"
      result = JSON.parse(response.body).fetch('result')
      assert_kind_of Array, result['content'], "#{name} content should be an array"
      assert_includes [true, false], result['isError'], "#{name} isError should be boolean"
    end
  end

  test 'notification gets a 202 with no body' do
    post_mcp(jsonrpc: '2.0', method: 'notifications/initialized')

    assert_response :accepted
    assert_empty response.body
  end

  test 'malformed JSON yields a JSON-RPC parse error' do
    post '/mcp', params: '{not json', headers: HEADERS

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal(-32700, body.dig('error', 'code'))
  end

  test 'GET is not allowed (no SSE stream in stateless mode)' do
    get '/mcp'
    assert_response :method_not_allowed
  end
end
