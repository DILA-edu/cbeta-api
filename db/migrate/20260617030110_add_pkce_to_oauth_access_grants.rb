# frozen_string_literal: true

# Adds PKCE (Proof Key for Code Exchange) columns required by Doorkeeper 5.x.
# Needed for MCP remote clients (e.g. claude.ai) that use authorization_code + S256.
class AddPkceToOauthAccessGrants < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth_access_grants, :code_challenge,        :string, null: true
    add_column :oauth_access_grants, :code_challenge_method, :string, null: true
  end
end
