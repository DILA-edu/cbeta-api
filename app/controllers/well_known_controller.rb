# frozen_string_literal: true

# Serves OAuth 2.0 discovery metadata required by MCP remote clients (e.g. claude.ai).
# RFC 8414 — Authorization Server Metadata
# RFC 9728 — Protected Resource Metadata
#
# Path-based discovery is supported: clients may append the resource path after the
# well-known suffix (e.g. /.well-known/oauth-protected-resource/dev/mcp), and any
# trailing path component is simply ignored — the correct metadata is returned based
# on the Rails environment via config.x.app_base_url.
class WellKnownController < ApplicationController
  def oauth_authorization_server
    base = Rails.application.config.x.app_base_url
    render json: {
      issuer:                                base,
      authorization_endpoint:                "#{base}/oauth/authorize",
      token_endpoint:                        "#{base}/oauth/token",
      registration_endpoint:                 "#{base}/oauth/register",
      response_types_supported:              %w[code],
      grant_types_supported:                 %w[authorization_code],
      code_challenge_methods_supported:      %w[S256],
      token_endpoint_auth_methods_supported: %w[client_secret_basic client_secret_post none]
    }
  end

  def oauth_protected_resource
    base = Rails.application.config.x.app_base_url
    render json: {
      resource:                 "#{base}/mcp",
      authorization_servers:    [base],
      bearer_methods_supported: %w[header],
      scopes_supported:         []
    }
  end
end
