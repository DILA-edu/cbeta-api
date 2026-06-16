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
      'search'              => :all_in_one,
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

    # Normalize the raw all_in_one payload into flat result items for the
    # platform-friendly /search surface, then delegate to ToolEnvelope.
    def my_render(data)
      if @_v1_tool_name == 'search' && !(data.is_a?(Hash) && data[:error])
        data = normalize_search_result(data)
      end
      super
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
      when 'search'
        # Platform-friendly surface: accepts `query` instead of `q`.
        return tool_error(code: 400, message: 'Missing required parameter: query') if params[:query].to_s.strip.empty?
        params[:q] = params[:query]
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

    # Flatten all_in_one results (one row per juan) into one item per kwic hit.
    # Each item carries the linehead as id so it can be passed directly to fetch.
    def normalize_search_result(raw)
      return { results: [] } unless raw.is_a?(Hash)

      items = []
      (raw[:results] || []).each do |juan|
        kwics = juan[:kwics]
        next unless kwics.is_a?(Hash)

        (kwics[:results] || []).each do |kwic|
          linehead = kwic[:linehead].to_s
          next if linehead.empty?

          items << {
            id: linehead,
            title: juan[:title].to_s,
            url: cbeta_online_url(juan[:work], juan[:juan]),
            metadata: {
              canon:     juan[:canon],
              category:  juan[:category],
              work:      juan[:work],
              file:      juan[:file],
              juan:      juan[:juan],
              byline:    juan[:byline],
              term_hits: juan[:term_hits],
              kwic:      kwic[:kwic],
              lb:        kwic[:lb],
              vol:       kwic[:vol]
            }.compact
          }
        end
      end

      { results: items }
    end

    def cbeta_online_url(work, juan)
      "https://cbetaonline.dila.edu.tw/#{work}_%03d" % juan.to_i
    end
  end
end
