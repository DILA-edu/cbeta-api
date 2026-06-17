# frozen_string_literal: true

Doorkeeper.configure do
  orm :active_record

  # Public MCP API — no user authentication needed.
  # Return a minimal object so Doorkeeper can store resource_owner_id = 0.
  resource_owner_authenticator do
    Struct.new(:id).new(0)
  end

  # Auto-approve all authorization requests (no approval screen shown to the user).
  skip_authorization { true }

  grant_flows %w[authorization_code]

  access_token_expires_in 7200 # 2 hours
end
