# frozen_string_literal: true

# MCP (Model Context Protocol) Streamable HTTP endpoint.
#
# A single route (POST /mcp) accepts JSON-RPC 2.0 messages and dispatches them
# through Mcp::Server. This is a stateless JSON-mode implementation: each POST
# returns a single JSON response (application/json) and no session id is
# assigned. The server does not open an SSE stream, so GET/DELETE return 405.
#
# The exposed tools mirror the /v1/tools/* HTTP surface (see public/openapi.json
# and TOOLS below). Each MCP tool dispatches in-process to its V1 controller.
class McpController < ApplicationController
  TOOLS = [
    Mcp::FindPassagesTool,
    Mcp::SearchNotesTool,
    Mcp::ExpandVariantsTool,
    Mcp::ExpandSynonymsTool,
    Mcp::ConvertSimplifiedTool,
    Mcp::SearchSimilarTool,
    Mcp::ResolveCitationTool,
    Mcp::GetContextTool
  ].freeze

  # When the body is sent as application/json, Rails parses params in middleware
  # before the action runs, so a malformed body raises here. Turn it into a
  # JSON-RPC parse error rather than the default 400 HTML page.
  rescue_from ActionDispatch::Http::Parameters::ParseError do
    render json: Mcp::Server.parse_error
  end

  def handle
    case request.request_method
    when 'POST'
      handle_post
    else
      # No server-initiated SSE stream / session to manage in stateless mode.
      head :method_not_allowed
    end
  end

  private

  def handle_post
    message =
      begin
        JSON.parse(request.raw_post)
      rescue JSON::ParserError
        return render json: Mcp::Server.parse_error
      end

    result = mcp_server.handle(message)

    if result.nil?
      # Body contained only notifications/responses.
      head :accepted
    else
      render json: result
    end
  end

  def mcp_server
    @mcp_server ||= Mcp::Server.new(tools: TOOLS.map(&:new))
  end
end
