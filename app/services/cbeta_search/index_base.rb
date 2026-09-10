module CbetaSearch
  # 各個 Elasticsearch index 的共同基底：analyzer、similarity、建立、匯入、alias 切換。
  #
  # 子類別（TextIndex / NotesIndex / TitlesIndex / ChunksIndex）只需宣告
  # key、mapping 與各自的欄位／排序設定，見 doc/elasticsearch-migration.md。
  #
  # 匯入來源一律是 rake search_xml:* 產出的 data/search-xml/*.xml —— 與舊 Manticore
  # 流程完全同一份轉檔輸出，因此搜尋結果的一致性最高。
  class IndexBase
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
    # 舊 Manticore 四個 index 的 charset_table / ngram 設定逐字相同，
    # 因此這一套 analyzer 四個 index 共用。
    #
    # 拉丁字母範圍: ASCII、Latin-1 Supplement (排除 × ÷ 兩個符號)、
    # Latin Extended-A/B、Latin Extended Additional (梵巴文轉寫的 ṣ ṭ ḥ 等)。
    TOKEN_PATTERN = '[A-Za-z0-9\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u024F\\u1E00-\\u1EFF]+|[^\\s]'.freeze

    # TOKEN_PATTERN 的 Ruby 版，用來算查詢詞的 token 數
    # (CbetaSearch::ElasticQueryBuilder#scored_phrase 要用它把 _score 正規化)。
    # 必須與 TOKEN_PATTERN 同語意 —— test/services/cbeta_search/text_index_test.rb
    # 會拿實際 index 的 _analyze 輸出比對，避免兩份規則走偏。
    TOKEN_RE = /[A-Za-z0-9À-ÖØ-öø-ɏḀ-ỿ]+|[^\s]/

    # start 參數上限。舊 API 允許 start 最大 99,999，ES 預設 from+size 只到 10,000。
    MAX_RESULT_WINDOW = 100_000

    # 每個 bulk request 的文件數。子類別可依文件大小調整。
    DEFAULT_BATCH_SIZE = 200

    # 查詢詞經 analyzer 之後的 token 數。
    def self.token_count(text)
      text.to_s.scan(TOKEN_RE).size
    end

    class << self
      # index 種類代號，同時是 config.x.elasticsearch.aliases / xml 的 key。
      def key
        raise NotImplementedError, "#{name} 必須實作 .key"
      end

      def index_alias
        Rails.configuration.x.elasticsearch.aliases.fetch(key)
      end

      def xml_path
        Rails.configuration.x.elasticsearch.xml.fetch(key)
      end

      # 版本化的 index 名稱，例 cbeta_notes_2026r3_001。
      #
      # 由 alias 推導而不是寫死 "cbeta_" 前綴: staging 與 production 是同一台機器、
      # 共用同一個 Elasticsearch，index 名稱撞在一起會互相覆蓋。
      #   cbeta_notes_current  (production) → cbeta_notes_2026r3_001
      #   cbeta_notes_staging  (staging)    → cbeta_notes_staging_2026r3_001
      def versioned_index_name(release, serial = '001')
        base = index_alias.delete_suffix('_current')
        "#{base}_#{release.to_s.downcase}_#{serial}"
      end

      def batch_size
        self::DEFAULT_BATCH_SIZE
      end

      # XmlpipeReader 的欄位型別轉換設定
      def integer_fields = [].freeze
      def array_integer_fields = [].freeze

      # 搜尋時要取回的 _source 欄位
      def source_fields
        raise NotImplementedError, "#{name} 必須實作 .source_fields"
      end

      # API 的 order 欄位 → ES 欄位
      def sort_fields = {}.freeze

      # 無 order 參數時的預設排序
      def default_sort = [].freeze

      # 排序值相同時的最後比較依據，讓分頁結果可預期
      def tiebreaker = [].freeze

      # 全文搜尋的預設欄位
      def default_field = 'content'.freeze

      # 單筆結果的輸出欄位: 輸出 key => _source 欄位名。
      # 順序刻意與舊 Manticore 的 SELECT 欄位順序一致，讓 JSON 輸出不變。
      def row_fields
        raise NotImplementedError, "#{name} 必須實作 .row_fields"
      end

      # 是否在單筆結果附上 id (舊版 SELECT 的第一個欄位)
      def row_id? = true

      # 是否在單筆結果附上 term_hits (舊版的 weight())
      def row_term_hits? = false

      # xmlpipe2 的欄位是選填的: 例如沒有作譯者的典籍，chunks.xml 裡就不會有
      # <creators_with_id>。Manticore 對缺少的 attribute 會回空字串 (uint 回 0)，
      # Elasticsearch 則是 _source 裡根本沒有這個欄位。
      # 為了讓 JSON 輸出與舊版一致 (實測 /dev 的 search/similar 回 "")，補回預設值。
      def row_default(field)
        integer_fields.include?(field) ? 0 : ''
      end
    end

    attr_reader :client

    def initialize(client: ElasticClient.build)
      @client = client
    end

    def key = self.class.key
    def index_alias = self.class.index_alias

    def create!(index_name = index_alias)
      client.indices.delete(index: index_name, ignore_unavailable: true)
      client.indices.create(index: index_name, body: index_body)
    end

    # 匯入 Manticore xmlpipe2 XML。回傳匯入筆數。
    def import!(xml_path: self.class.xml_path, index_name: index_alias, batch_size: self.class.batch_size)
      reader = XmlpipeReader.new(
        xml_path,
        integer_fields: self.class.integer_fields,
        array_integer_fields: self.class.array_integer_fields
      )
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
    def promote!(index_name, alias_name: index_alias)
      actions = current_aliases(alias_name).keys.map do |old_index|
        { remove: { index: old_index, alias: alias_name } }
      end
      actions << { add: { index: index_name, alias: alias_name } }

      client.indices.update_aliases(body: { actions: })
    end

    def analyze(text, index_name: index_alias)
      client.indices.analyze(index: index_name, body: { analyzer: ANALYZER, text: })
    end

    def index_body
      {
        settings: index_settings,
        mappings: mappings
      }
    end

    # 子類別實作
    def mappings
      raise NotImplementedError, "#{self.class.name} 必須實作 #mappings"
    end

    private

    def index_settings
      {
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
      }
    end

    # 會計分的全文欄位。term_vector 刻意不開: 只有 ES highlight 需要，
    # 本專案 KWIC 走既有 KwicService。
    #
    # norms 一定要關掉，有兩個理由:
    #   1. TERM_FREQ_SCRIPT 只用 doc.freq，不用 doc.length，norms 純屬浪費空間。
    #   2. 開著會踩到 Elasticsearch 的 bug: 「OR 查詢 + scripted_metric 讀 _score」
    #      在資料量大時，ScriptedSimilarity 會對已走完的 scorer (docID =
    #      Integer.MAX_VALUE) 去讀 norms，整個查詢回 500
    #      (read past EOF (pos=2147483647) ... .nvd)。
    #      實測 2,182,414 筆的 notes index 必現，22,037 筆的 text index 不會 ——
    #      是規模相依的，所以兩個 index 都要關。
    def term_freq_field
      {
        type: 'text',
        analyzer: ANALYZER,
        similarity: TERM_FREQ_SIMILARITY,
        norms: false
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

    # 只回傳、不搜尋的欄位。2 百萬筆的 notes index 若把這些也建倒排索引，
    # index 會白白大一倍。
    def stored_only_mapping
      { type: 'keyword', index: false, doc_values: false }
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
