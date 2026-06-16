# frozen_string_literal: true

# Shared rendering envelope for /v1/tools/* endpoints.
#
# Wraps the underlying controller's response in the normalized tool contract
# defined in public/openapi.json:
#
#   success: { ok: true,  tool:, request_id:, data: {...} }
#   error:   { ok: false, tool:, request_id:, error_code:, message:, retryable: }
#
# Including controllers can keep their existing `my_render` call sites; this
# concern overrides `my_render` to translate raw result hashes into envelopes.
# Errors emitted as `{ error: { code:, message: } }` (the convention used by
# SearchController and JuansController) are converted into the error envelope.
#
# `tool_name` is derived from `@_v1_tool_name` when present (V1::ToolsController
# swaps action_name to the underlying SearchController action; the original V1
# tool name is preserved here) and falls back to `action_name` otherwise.
module ToolEnvelope
  extend ActiveSupport::Concern

  ENVELOPE_EXCLUDED_KEYS = %i[SQL backtrace].freeze

  private

  def tool_name
    @_v1_tool_name || action_name
  end

  def my_render(data)
    if data.is_a?(Hash) && data[:error]
      err = data[:error]
      if err.is_a?(Hash)
        tool_error(code: err[:code] || 500, message: err[:message])
      else
        tool_error(code: 500, message: err)
      end
    else
      data = data.except(*ENVELOPE_EXCLUDED_KEYS) if data.is_a?(Hash)
      render json: {
        ok: true,
        tool: tool_name,
        request_id: request.request_id,
        data: data
      }
    end
  end

  def tool_error(code:, message:)
    c = code.to_i
    render status: tool_http_status(c), json: {
      ok: false,
      tool: tool_name,
      request_id: request.request_id,
      error_code: tool_error_code(c),
      message: message.to_s,
      retryable: tool_retryable?(c)
    }
  end

  def tool_error_code(code)
    case code
    when 400 then 'invalid_request'
    when 404 then 'not_found'
    when 504 then 'upstream_timeout'
    else 'internal_error'
    end
  end

  def tool_retryable?(code)
    [500, 502, 503, 504].include?(code)
  end

  def tool_http_status(code)
    (400..599).include?(code) ? code : 500
  end

  def tool_error_handler(e)
    Rails.logger.fatal(e.message)
    Rails.logger.fatal(e.backtrace.join("\n")) if e.backtrace
    code = e.is_a?(CbetaError) ? e.code : 500
    tool_error(code: code, message: e.message)
  end
end
