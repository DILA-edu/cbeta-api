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

  test 'tools/list exposes find_passages with an input schema' do
    post_mcp(jsonrpc: '2.0', id: 2, method: 'tools/list')

    assert_response :success
    tools = JSON.parse(response.body).dig('result', 'tools')
    names = tools.map { |t| t['name'] }
    assert_includes names, 'find_passages'

    schema = tools.find { |t| t['name'] == 'find_passages' }['inputSchema']
    assert_includes schema['required'], 'q'
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
