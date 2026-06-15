# frozen_string_literal: true

require 'faraday'
require 'json'

module Mcp
  # MCP tool wrapping the +POST /v1/tools/find_passages+ HTTP endpoint.
  #
  # The tool is a thin client: it forwards the given arguments as the JSON body
  # to the upstream CBETA API (base URL configurable via the CBETA_API_BASE_URL
  # environment variable) and re-packages the normalized tool envelope into an
  # MCP tool result (text content + structuredContent).
  class FindPassagesTool
    NAME = 'find_passages'
    PATH = '/v1/tools/find_passages'
    DEFAULT_BASE_URL = 'http://localhost:3000'
    DEFAULT_TIMEOUT = 60
    DEFAULT_OPEN_TIMEOUT = 10

    def name
      NAME
    end

    def description
      <<~DESC.strip
        Search the CBETA Buddhist canon full text and return matching passages
        with surrounding KWIC context. Use the official extended query grammar
        (AND = space-separated quoted terms, OR = |, NOT = !, NEAR = NEAR/n).

        在 CBETA 佛典全文中搜尋詞彙,回傳符合的卷次與前後文 (KWIC)。
        查詢語法:AND 用空白分隔的引號詞、OR 用 |、NOT 用 !、NEAR 用 NEAR/n。
      DESC
    end

    # JSON Schema for the tool arguments, mirroring the requestBody schema in
    # public/openapi.json so the contract stays in one shape.
    def input_schema
      {
        type: 'object',
        required: ['q'],
        additionalProperties: false,
        properties: {
          q: {
            type: 'string',
            description: 'Query expression in the official extended search grammar. Passed byte-for-byte to upstream; do not normalize.'
          },
          rows: {
            type: 'integer',
            minimum: 1,
            maximum: 100,
            default: 20,
            description: 'Number of results (juan) to return.'
          },
          around: {
            type: 'integer',
            minimum: 0,
            default: 50,
            description: 'Context characters around each hit.'
          },
          canon: {
            type: 'string',
            description: 'Comma-separated CBETA canon ids (e.g. "T" or "T,X").'
          },
          category: {
            type: 'string',
            description: 'Category expression using a,b+c,d grammar where + is AND and , is OR (e.g. 阿含部類, 般若部類).'
          },
          creator: {
            type: 'string',
            description: 'Creator (author/translator) IDs, not display names. Each id is [A-Z] followed by six digits (e.g. A000420). Supports a,b+c,d grammar.'
          },
          dynasty: {
            type: 'string',
            description: 'Dynasty filter.'
          },
          time: {
            type: 'string',
            description: 'Single year (e.g. "800") or an inclusive range using .. (e.g. "800..900").'
          },
          work: {
            type: 'string',
            description: 'Single work id.'
          },
          works: {
            type: 'string',
            description: 'Comma-separated work ids.'
          },
          work_type: {
            type: 'string',
            enum: %w[textbody non-textbody],
            description: 'Restrict to scripture body or non-body works.'
          },
          start: {
            type: 'integer',
            minimum: 0,
            description: 'Result offset for pagination.'
          },
          facet: {
            type: 'string',
            description: 'Optional facet specifier.'
          }
        }
      }
    end

    def call(arguments)
      response = connection.post(PATH) do |req|
        req.headers['Content-Type'] = 'application/json'
        req.headers['Accept'] = 'application/json'
        req.body = JSON.generate(arguments)
      end

      build_result(parse_json(response.body))
    rescue Faraday::Error => e
      tool_error("無法連線 CBETA API (#{base_url}): #{e.message}")
    end

    private

    def connection
      @connection ||= Faraday.new(url: base_url) do |f|
        f.options.timeout = DEFAULT_TIMEOUT
        f.options.open_timeout = DEFAULT_OPEN_TIMEOUT
      end
    end

    def base_url
      ENV.fetch('CBETA_API_BASE_URL', DEFAULT_BASE_URL)
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError, TypeError
      nil
    end

    def build_result(payload)
      return tool_error('CBETA API 回傳非預期的內容 (無法解析為 JSON)') if payload.nil?

      if payload['ok']
        data = payload['data'] || {}
        {
          content: [
            { type: 'text', text: summarize(data) },
            { type: 'text', text: JSON.generate(data) }
          ],
          structuredContent: data,
          isError: false
        }
      else
        message = payload['message'] || 'CBETA API 回報錯誤'
        tool_error(message, structured: payload)
      end
    end

    # Short, human-readable header that works for clients that only read text
    # content. Full data is carried in structuredContent and the second block.
    def summarize(data)
      num_found = data['num_found']
      total_hits = data['total_term_hits']
      query = data['query_string']
      results = data['results'] || []

      lines = ["查詢「#{query}」:找到 #{num_found} 卷,總命中 #{total_hits} 次。"]
      results.each do |r|
        title = r['title']
        juan = r['juan']
        hits = r['term_hits']
        canon = r['canon']
        lines << "- [#{canon}] #{title} 卷#{juan} (#{hits} 次)"
      end
      lines.join("\n")
    end

    def tool_error(message, structured: nil)
      result = {
        content: [{ type: 'text', text: message }],
        isError: true
      }
      result[:structuredContent] = structured if structured
      result
    end
  end
end
