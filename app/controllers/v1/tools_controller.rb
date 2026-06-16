# frozen_string_literal: true

# v1/tools/* — thin tool-surface wrappers around SearchController actions.
#
# Each V1 tool action calls a private SearchController method (all_in_one,
# notes, variants, synonym, sc, similar). The full search machinery (init,
# KWIC, facet, similar smith-waterman, …) is reused unchanged; only the
# rendering envelope changes (see ToolEnvelope).
#
# SearchController#init dispatches on action_name (notes/similar/variants/etc.)
# to wire @index / @fields / @gain / @penalty correctly. To keep that branching
# intact, +v1_setup_tool_name+ swaps action_name to the underlying name BEFORE
# init runs, and stashes the V1 tool name in @_v1_tool_name (used by the
# envelope). Rails dispatches to the V1 action method first (e.g. +search_notes+)
# because process_action's method name is bound from the route, not from
# action_name; the swap only affects what action_name returns to init.
module V1
  class ToolsController < SearchController
    include ToolEnvelope

    # V1 tool name -> underlying SearchController action method.
    UNDERLYING_ACTIONS = {
      'find_passages'       => :all_in_one,
      'search_notes'        => :notes,
      'expand_variants'     => :variants,
      'expand_synonyms'     => :synonym,
      'convert_simplified'  => :sc,
      'search_similar'      => :similar
    }.freeze

    # Order matters: v1_setup_tool_name must run before v1_prepare_request
    # (the latter reads @_v1_tool_name), and both must run before :init.
    prepend_before_action :v1_prepare_request
    prepend_before_action :v1_setup_tool_name

    UNDERLYING_ACTIONS.each do |tool, underlying|
      define_method(tool) { send(underlying) }
    end

    private

    # Stash the V1 tool name and swap action_name so SearchController#init's
    # case branch sees the underlying name (notes/similar/variants/etc.).
    def v1_setup_tool_name
      underlying = UNDERLYING_ACTIONS[action_name]
      return unless underlying

      @_v1_tool_name = action_name
      @_action_name = underlying.to_s
    end

    # Validate input and apply contract-level defaults / type coercions before
    # SearchController#init reads params.
    def v1_prepare_request
      case @_v1_tool_name
      when 'find_passages', 'search_notes'
        return if missing_q?
        # openapi.json documents around's default as 50 (SearchController#init
        # otherwise falls back to 10).
        params[:around] = 50 unless params.key?(:around)
      when 'expand_variants', 'expand_synonyms', 'convert_simplified'
        missing_q?
      when 'search_similar'
        return if missing_q?
        # SearchController#init reads cache/facet via `== '1'`, so integer
        # 0/1 from the JSON body must be coerced to strings.
        params[:cache] = params[:cache].to_s if params.key?(:cache)
        params[:facet] = params[:facet].to_s if params.key?(:facet)
      end
    end

    def missing_q?
      return false unless params[:q].to_s.strip.empty?
      tool_error(code: 400, message: 'Missing required parameter: q')
      true
    end

    # SearchController catches Exception with :error_handler and renders the
    # raw error hash through my_render. Override to render the envelope.
    def error_handler(e)
      tool_error_handler(e)
    end
  end
end
