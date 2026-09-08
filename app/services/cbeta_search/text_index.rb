module CbetaSearch
  # CBETA text index 的 mapping 定義、建立、匯入與 alias 切換。
  #
  # 匯入來源是既有 Manticore 轉檔流程產出的 data/manticore-xml/text.xml，
  # 與 Manticore 完全同源，因此搜尋結果的一致性最高。
  # text.xml 裡的 content 已經去標點，ES 不需要再做任何正規化。
  class TextIndex
    # 每個 bulk request 的文件數。text.xml 平均每卷約 60KB、兩個 content 欄位，
    # 200 卷約 24MB，遠低於 ES 預設的 http.max_content_length (100MB)。
    DEFAULT_BATCH_SIZE = 200

    # 「score = 詞頻」的 scripted similarity。
    # 這是取代 Manticore ranker=wordcount 的關鍵: phrase 查詢每份文件的
    # _score 等於「出現次數 × 詞長」(Lucene 對 phrase 的每個 term 各執行一次
    # script 再相加)，因此 term_hits 可直接由 _score 還原，毋須逐卷讀檔。
    TERM_FREQ_SIMILARITY = 'term_freq'.freeze
    TERM_FREQ_SCRIPT = 'return doc.freq;'.freeze

    ANALYZER = 'cbeta_text'.freeze

    # Token 切分規則，對應 Manticore 的 charset_table = non_cjk + ngram_len = 1：
    #   * 連續的拉丁字母 / 數字 → 一個 token (與 non_cjk 的 word 切分一致)
    #   * 其他任何非空白字元 → 各自一個 token (與 ngram_len = 1 的逐字切分一致)
    #
    # 不能改用 standard tokenizer: 它會丟掉「□」(U+25A1)、「▆」(U+2586) 與 PUA 缺字，
    # 而這三者在 CBETA 都是有意義的正文字元 (見 CbetaString 的 FULL_PUNCS 註解)。
    # 也不能用純 ngram(1,1): 那會讓拉丁文逐字元切開，搜「Ananda」會誤中
    # 「Pannananda」「Śikṣānanda」等較長字的子字串 (實測比 Manticore 多出 14 卷)。
    #
    # 拉丁字母範圍: ASCII、Latin-1 Supplement (排除 × ÷ 兩個符號)、
    # Latin Extended-A/B、Latin Extended Additional (梵巴文轉寫的 ṣ ṭ ḥ 等)。
    TOKEN_PATTERN = '[A-Za-z0-9\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u024F\\u1E00-\\u1EFF]+|[^\\s]'.freeze

    # TOKEN_PATTERN 的 Ruby 版，用來算查詢詞的 token 數
    # (CbetaSearch::ElasticQueryBuilder#scored_phrase 要用它把 _score 正規化)。
    # 必須與 TOKEN_PATTERN 同語意 —— test/services/cbeta_search/text_index_test.rb
    # 會拿實際 index 的 _analyze 輸出比對，避免兩份規則走偏。
    TOKEN_RE = /[A-Za-z0-9\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u024F\u1E00-\u1EFF]+|[^\s]/

    # 查詢詞經 analyzer 之後的 token 數。
    def self.token_count(text)
      text.to_s.scan(TOKEN_RE).size
    end

    # start 參數上限。舊 API 允許 start 最大 99,999，ES 預設 from+size 只到 10,000。
    MAX_RESULT_WINDOW = 100_000

    attr_reader :client

    def initialize(client: ElasticClient.build)
      @client = client
    end

    def create!(index_name = configured_index_name)
      client.indices.delete(index: index_name, ignore_unavailable: true)
      client.indices.create(index: index_name, body: index_body)
    end

    # 匯入 Manticore text.xml。回傳匯入筆數。
    def import!(xml_path:, index_name: configured_index_name, batch_size: DEFAULT_BATCH_SIZE)
      reader = ManticoreTextXmlReader.new(xml_path)
      imported = 0

      reader.each.each_slice(batch_size) do |docs|
        operations = docs.flat_map do |doc|
          id = doc.delete('_id')
          [{ index: { _index: index_name, _id: id } }, doc]
        end

        response = client.bulk(body: operations)
        raise_bulk_error!(response) if response['errors']

        imported += docs.size
        yield imported if block_given?
      end

      client.indices.refresh(index: index_name)
      imported
    end

    # 把 alias 原子切換到指定 index。
    def promote!(index_name = configured_index_name, alias_name: configured_index_alias)
      actions = current_aliases(alias_name).keys.map do |old_index|
        { remove: { index: old_index, alias: alias_name } }
      end
      actions << { add: { index: index_name, alias: alias_name } }

      client.indices.update_aliases(body: { actions: })
    end

    def analyze(text, index_name: configured_index_name)
      client.indices.analyze(index: index_name, body: { analyzer: ANALYZER, text: })
    end

    def index_body
      {
        settings: {
          'index.number_of_replicas' => 0, # 單節點，避免 cluster 停在 yellow
          'index.max_result_window' => MAX_RESULT_WINDOW,
          similarity: {
            TERM_FREQ_SIMILARITY => {
              type: 'scripted',
              script: { source: TERM_FREQ_SCRIPT }
            }
          },
          analysis: {
            analyzer: {
              ANALYZER => {
                tokenizer: 'cbeta_tokenizer',
                # asciifolding 對應 Manticore charset_table = non_cjk 的變音符號折疊
                # (實測 production: 搜 Ananda 與 Ānanda 同樣得到 52 卷)。
                # 只影響拉丁字母，CJK、PUA 缺字、康熙部首都不受影響。
                filter: %w[lowercase asciifolding]
              }
            },
            tokenizer: {
              cbeta_tokenizer: {
                type: 'pattern',
                pattern: TOKEN_PATTERN,
                group: 0
              }
            }
          }
        },
        mappings: {
          # content 全文不需要回傳(顯示端走 KwicService)，排除以節省 _source 空間。
          # 這與 Manticore 現況一致(text.conf 用 xmlpipe_field，不存原文)。
          # term_freq 計分走倒排索引，不受此影響。
          _source: { excludes: %w[content content_without_notes] },
          properties: {
            content: text_field_mapping,
            content_without_notes: text_field_mapping,
            canon: keyword_mapping,
            canon_order: keyword_mapping,
            category: keyword_mapping,
            file: keyword_mapping,
            vol: keyword_mapping,
            work: keyword_mapping,
            work_type: keyword_mapping,
            dynasty: keyword_mapping,
            juan_list: keyword_mapping,
            alt: keyword_mapping,
            title: text_and_keyword_mapping,
            byline: text_and_keyword_mapping,
            creators: text_and_keyword_mapping,
            creators_with_id: text_and_keyword_mapping,
            category_ids: { type: 'integer' },
            creator_id: { type: 'integer' },
            juan: { type: 'integer' },
            juan_start: { type: 'integer' },
            time_from: { type: 'integer' },
            time_to: { type: 'integer' }
          }
        }
      }
    end

    private

    def configured_index_name
      Rails.configuration.x.elasticsearch.index_name
    end

    def configured_index_alias
      Rails.configuration.x.elasticsearch.index_alias
    end

    # term_vector 刻意不開: 只有 ES highlight 需要，本專案 KWIC 走既有 KwicService。
    def text_field_mapping
      {
        type: 'text',
        analyzer: ANALYZER,
        similarity: TERM_FREQ_SIMILARITY
      }
    end

    def keyword_mapping
      { type: 'keyword' }
    end

    def text_and_keyword_mapping
      {
        type: 'text',
        analyzer: ANALYZER,
        fields: { keyword: { type: 'keyword', ignore_above: 512 } }
      }
    end

    def current_aliases(alias_name)
      client.indices.get_alias(name: alias_name, ignore_unavailable: true)
    rescue Elastic::Transport::Transport::Errors::NotFound
      {}
    end

    def raise_bulk_error!(response)
      item = response.fetch('items').find { |entry| entry.dig('index', 'error') }
      raise CbetaError.new(500), "Elasticsearch bulk import 失敗：#{item.dig('index', 'error', 'reason')}"
    end
  end
end
