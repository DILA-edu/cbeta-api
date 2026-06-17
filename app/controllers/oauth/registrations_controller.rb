# frozen_string_literal: true

# RFC 7591 — Dynamic Client Registration
# Allows MCP clients (e.g. claude.ai) to register as an OAuth application on the fly.
module Oauth
  class RegistrationsController < ApplicationController
    def create
      app = Doorkeeper::Application.new(
        name:         params[:client_name].presence || "MCP Client #{SecureRandom.hex(4)}",
        redirect_uri: Array(params[:redirect_uris]).join("\n"),
        scopes:       "",
        confidential: params[:token_endpoint_auth_method] != "none"
      )

      if app.save
        render json: {
          client_id:                  app.uid,
          client_secret:              app.confidential? ? app.secret : nil,
          client_id_issued_at:        app.created_at.to_i,
          client_name:                app.name,
          redirect_uris:              app.redirect_uri.split("\n"),
          grant_types:                ["authorization_code"],
          response_types:             ["code"],
          token_endpoint_auth_method: app.confidential? ? "client_secret_basic" : "none"
        }.compact, status: :created
      else
        render json: {
          error:             "invalid_client_metadata",
          error_description: app.errors.full_messages.join(", ")
        }, status: :bad_request
      end
    end
  end
end
