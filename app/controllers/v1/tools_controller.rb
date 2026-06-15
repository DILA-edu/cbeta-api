# frozen_string_literal: true

# v1/tools/find_passages
#
# Thin tool-surface wrapper around SearchController#all_in_one, contract
# defined in public/openapi.json. It reuses every bit of the existing search
# machinery (init, all_in_one_sub, kwic, facet, exclude/near…) and only swaps
# the rendering layer so responses use the normalized tool envelope:
#
#   success: { ok: true,  tool:, request_id:, data: { ...all_in_one result... } }
#   error:   { ok: false, tool:, request_id:, error_code:, message:, retryable: }
#
# Input is a JSON body whose keys (q, rows, around, canon, category, creator,
# dynasty, time, work, works, work_type, start, facet) map directly onto the
# params SearchController already reads, so no parameter translation is needed.
module V1
  class ToolsController < SearchController
    TOOL_NAME = 'find_passages'

    # Run before SearchController's :init so we can validate input and apply the
    # contract's defaults before the search machinery reads params.
    prepend_before_action :prepare_find_passages, only: :find_passages

    def find_passages
      all_in_one
    end

    private

    def prepare_find_passages
      if params[:q].to_s.strip.empty?
        tool_error(code: 400, message: 'Missing required parameter: q')
        return false
      end

      # openapi.json documents around's default as 50 (SearchController#init
      # otherwise falls back to 10).
      params[:around] = 50 unless params.key?(:around)
    end

    # SearchController renders every result (success and error) through
    # my_render. Override it to emit the tool envelope instead of the raw hash.
    def my_render(data)
      if data.is_a?(Hash) && data[:error]
        err = data[:error]
        if err.is_a?(Hash)
          tool_error(code: err[:code] || 500, message: err[:message])
        else
          tool_error(code: 500, message: err)
        end
      else
        data = data.except(:SQL, :backtrace) if data.is_a?(Hash)
        render json: {
          ok: true,
          tool: TOOL_NAME,
          request_id: request.request_id,
          data: data
        }
      end
    end

    # Catches anything not handled by all_in_one's inline rescues (e.g. errors
    # raised inside the :init before_action).
    def error_handler(e)
      logger.fatal e.message
      logger.fatal e.backtrace.join("\n") if e.backtrace
      code = e.is_a?(CbetaError) ? e.code : 500
      tool_error(code: code, message: e.message)
    end

    def tool_error(code:, message:)
      c = code.to_i
      render status: http_status(c), json: {
        ok: false,
        tool: TOOL_NAME,
        request_id: request.request_id,
        error_code: error_code(c),
        message: message.to_s,
        retryable: retryable?(c)
      }
    end

    def error_code(code)
      case code
      when 400 then 'invalid_request'
      when 404 then 'not_found'
      when 504 then 'upstream_timeout'
      else 'internal_error'
      end
    end

    def retryable?(code)
      [500, 502, 503, 504].include?(code)
    end

    def http_status(code)
      (400..599).include?(code) ? code : 500
    end
  end
end
