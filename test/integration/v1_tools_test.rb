# frozen_string_literal: true

require 'test_helper'

# Integration tests for the /v1/tools/* HTTP surface.
#
# Most tools depend on the Manticore search backend (and a real Variant /
# Term table, opencc binary, …), which may not be available in CI. These
# tests therefore focus on the bits we can verify without external services:
#
#   * the contract envelope is well-formed on both success and error paths
#   * input validation rejects missing-required-parameter requests with the
#     normalized 400 envelope BEFORE any backend call is attempted
#
# Happy-path requests assert envelope shape only (ok ∈ {true, false}, tool
# name matches, request_id present), following the same pattern as the
# existing find_passages MCP integration test.
class V1ToolsTest < ActionDispatch::IntegrationTest
  HEADERS = { 'Content-Type' => 'application/json', 'User-Agent' => 'v1-tools-test' }.freeze

  TOOLS_REQUIRING_Q = %w[
    find_passages
    search_notes
    expand_variants
    expand_synonyms
    convert_simplified
    search_similar
  ].freeze

  def post_tool(name, payload)
    post "/v1/tools/#{name}", params: JSON.generate(payload), headers: HEADERS
  end

  def assert_error_envelope(tool_name)
    body = JSON.parse(response.body)
    assert_equal false, body['ok']
    assert_equal tool_name, body['tool']
    assert body['request_id'].present?, "request_id should be present"
    assert body['error_code'].present?, "error_code should be present"
    assert body['message'].present?, "message should be present"
    assert_includes [true, false], body['retryable']
  end

  def assert_envelope(tool_name)
    body = JSON.parse(response.body)
    assert_includes [true, false], body['ok'], "ok should be boolean"
    assert_equal tool_name, body['tool']
    assert body['request_id'].present?, "request_id should be present"
  end

  # --- Missing-required-parameter (400) tests -------------------------------

  TOOLS_REQUIRING_Q.each do |tool|
    test "POST /v1/tools/#{tool} without q returns 400 envelope" do
      post_tool(tool, {})
      assert_response :bad_request
      assert_error_envelope(tool)
      assert_equal 'invalid_request', JSON.parse(response.body)['error_code']
    end

    test "POST /v1/tools/#{tool} with blank q returns 400 envelope" do
      post_tool(tool, { q: '   ' })
      assert_response :bad_request
      assert_error_envelope(tool)
    end
  end

  # --- Query string length limit (400) -------------------------------------
  #
  # SearchController#init rejects a q longer than MAX_QUERY_LENGTH characters
  # before any backend call, so this is verifiable without the search backend.
  # convert_simplified has its own stricter 50-char limit (params[:q].size > 50,
  # checked in SearchController#sc), so it is excluded here.
  (TOOLS_REQUIRING_Q - %w[convert_simplified]).each do |tool|
    test "POST /v1/tools/#{tool} with over-long q returns 400 envelope" do
      post_tool(tool, { q: '佛' * (SearchController::MAX_QUERY_LENGTH + 1) })
      assert_response :bad_request
      assert_error_envelope(tool)
      assert_equal 'invalid_request', JSON.parse(response.body)['error_code']
    end
  end

  test 'POST /v1/tools/resolve_citation without linehead or canon returns 400' do
    post_tool('resolve_citation', {})
    assert_response :bad_request
    assert_error_envelope('resolve_citation')
  end

  test 'POST /v1/tools/get_context without linehead or range returns 400' do
    post_tool('get_context', {})
    assert_response :bad_request
    assert_error_envelope('get_context')
  end

  test 'POST /v1/tools/get_context with linehead_start but no linehead_end returns 400' do
    post_tool('get_context', { linehead_start: 'T01n0001_p0001a01' })
    assert_response :bad_request
    assert_error_envelope('get_context')
  end

  # --- Happy-path envelope shape -------------------------------------------
  #
  # These do not assert ok=true since the search backend may be unreachable
  # in CI; envelope shape is what's verified.

  test 'POST /v1/tools/find_passages returns envelope' do
    post_tool('find_passages', { q: '佛', rows: 1 })
    assert_envelope('find_passages')
  end

  test 'POST /v1/tools/search_notes returns envelope' do
    post_tool('search_notes', { q: '佛', rows: 1 })
    assert_envelope('search_notes')
  end

  test 'POST /v1/tools/expand_variants returns envelope' do
    post_tool('expand_variants', { q: '佛' })
    assert_envelope('expand_variants')
  end

  test 'POST /v1/tools/expand_synonyms returns envelope' do
    post_tool('expand_synonyms', { q: '佛' })
    assert_envelope('expand_synonyms')
  end

  test 'POST /v1/tools/convert_simplified returns envelope' do
    post_tool('convert_simplified', { q: '佛' })
    assert_envelope('convert_simplified')
  end

  test 'POST /v1/tools/search_similar returns envelope' do
    post_tool('search_similar', { q: '一切眾生皆有佛性', k: 1 })
    assert_envelope('search_similar')
  end

  test 'POST /v1/tools/resolve_citation with malformed linehead returns 400 envelope' do
    # JuansController#goto returns { error: { code: 400, message: ... } } for
    # an unrecognized linehead format; ToolEnvelope must translate that into
    # the normalized error envelope (and NOT bubble through as a 500).
    post_tool('resolve_citation', { linehead: 'this-is-not-a-valid-linehead' })
    assert_response :bad_request
    assert_error_envelope('resolve_citation')
  end

  test 'POST /v1/tools/get_context with linehead returns envelope' do
    post_tool('get_context', { linehead: 'T01n0001_p0001a01', before: 0, after: 0 })
    assert_envelope('get_context')
  end

  # --- envelope content sanity ---------------------------------------------

  test 'success envelope strips SQL and backtrace' do
    # On success ToolEnvelope strips :SQL / :backtrace before rendering. We
    # can't easily exercise the success path without the search backend, so
    # this just checks the keys are not present whenever ok=true (and
    # asserts envelope shape unconditionally).
    post_tool('expand_synonyms', { q: '佛' })
    assert_envelope('expand_synonyms')

    body = JSON.parse(response.body)
    return unless body['ok']

    data = body['data'] || {}
    refute data.key?('SQL'), 'SQL should be stripped from success envelope'
    refute data.key?('backtrace'), 'backtrace should be stripped from success envelope'
  end
end
