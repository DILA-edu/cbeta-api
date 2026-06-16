# frozen_string_literal: true

# v1/tools/resolve_citation — thin wrapper around JuansController#goto.
#
# Accepts either a free-text +linehead+ or structured citation fields
# (canon/work/juan/page/col/line). JuansController#goto already encapsulates
# all the parsing for CBETA's various citation formats; we just route into it
# and let ToolEnvelope translate the response.
module V1
  class CitationsController < JuansController
    include ToolEnvelope

    rescue_from StandardError, with: :tool_error_handler

    def resolve_citation
      if params[:linehead].to_s.strip.empty? && params[:canon].to_s.strip.empty?
        return tool_error(
          code: 400,
          message: 'Missing required parameter: linehead, or canon (with work/juan/page/col/line)'
        )
      end

      goto
    end
  end
end
