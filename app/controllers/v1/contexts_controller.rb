# frozen_string_literal: true

# v1/tools/get_context — thin wrapper around LinesController#index.
#
# Returns surrounding text lines for a single linehead anchor, or for a
# linehead_start/linehead_end range. Defaults follow public/openapi.json
# (before: 5, after: 5).
module V1
  class ContextsController < LinesController
    include ToolEnvelope

    rescue_from StandardError, with: :tool_error_handler

    def get_context
      lh = params[:linehead].to_s.strip
      lh_start = params[:linehead_start].to_s.strip
      lh_end = params[:linehead_end].to_s.strip

      if lh.empty? && (lh_start.empty? || lh_end.empty?)
        return tool_error(
          code: 400,
          message: 'Provide either linehead, or both linehead_start and linehead_end'
        )
      end

      params[:before] = 5 unless params.key?(:before)
      params[:after]  = 5 unless params.key?(:after)

      index
    end
  end
end
