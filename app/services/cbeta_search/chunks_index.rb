module CbetaSearch
  # 相似句 (chunks) index。匯入來源是 rake search_xml:chunks 產出的 chunks.xml
  # (每 100 字一塊、前後重疊 50 字)，是四個 index 中筆數最多、體積最大的。
  #
  # search#similar 只用 Elasticsearch 挑出 top k 候選，真正的比對與排序由 Ruby 端的
  # Smith-Waterman 完成，因此這裡要的是「相關度」而不是「出現次數」:
  # content 掛預設的 BM25，不掛 term_freq similarity。
  class ChunksIndex < IndexBase
    # 每筆約 100 字 + metadata，2,000 筆一批約 1MB。
    DEFAULT_BATCH_SIZE = 2_000

    # search#similar 第一階段的 quorum 門檻。
    # 舊版是 Manticore 的 MATCH('"<q>"/0.5') —— 一半的字命中即為候選。
    #
    # ES 的百分比 minimum_should_match 是無條件捨去 (7 字 → 3)，
    # Manticore 的進位方式未公開。字數為奇數時候選池的邊界因此可能差一個字，
    # 但候選最後都要過 Smith-Waterman，這個差異會被 BM25 的排序差異蓋過去。
    QUORUM_RATIO = '50%'.freeze

    # Smith-Waterman 要拿全文比對，content 一定要進 _source。
    SOURCE_FIELDS = %w[
      canon category work title juan creators_with_id dynasty linehead content
      position_in_juan
    ].freeze

    # 舊版 SQL 沒有 ORDER BY，靠 Manticore 的 proximity_bm25 相關度排序。
    DEFAULT_SORT = [{ '_score' => { 'order' => 'desc' } }].freeze

    # chunks.xml 沒有 canon_order 欄位，無法照其他 index 的慣例做 tiebreaker。
    # 改用 _doc (Lucene 內部順序，同一份 index 內穩定)，讓 top k 的取樣可重現。
    TIEBREAKER = %w[_doc].freeze

    # 對應舊 similar_sub 的 SELECT 欄位與順序。
    # position_in_juan 只給 similar_smith_waterman 判斷卷首／卷尾用，輸出前會被刪掉。
    ROW_FIELDS = {
      canon: 'canon',
      category: 'category',
      work: 'work',
      title: 'title',
      juan: 'juan',
      creators_with_id: 'creators_with_id',
      dynasty: 'dynasty',
      linehead: 'linehead',
      content: 'content',
      position_in_juan: 'position_in_juan'
    }.freeze

    class << self
      def key = :chunks
      def integer_fields = %w[juan time_from time_to].freeze
      def array_integer_fields = %w[category_ids creator_id].freeze
      def source_fields = SOURCE_FIELDS
      def default_sort = DEFAULT_SORT
      def tiebreaker = TIEBREAKER
      def row_fields = ROW_FIELDS
    end

    def mappings
      {
        properties: {
          # 唯一被搜尋的欄位。用預設的 BM25: 第一階段要的是相關度，不是出現次數，
          # 因此也不掛 term_freq similarity、不關 norms (BM25 要用文件長度)。
          content: {
            type: 'text',
            analyzer: ANALYZER
          },

          # 只有 filter 會用到的欄位才建索引。
          canon: keyword_mapping,
          work: keyword_mapping,
          dynasty: keyword_mapping,
          category_ids: { type: 'integer' },
          creator_id: { type: 'integer' },
          time_from: { type: 'integer' },
          time_to: { type: 'integer' },

          # 只回傳、不搜尋也不排序。這個 index 上千萬筆，多建一個倒排索引就多幾百 MB。
          category: stored_only_mapping,
          title: stored_only_mapping,
          creators: stored_only_mapping,
          creators_with_id: stored_only_mapping,
          linehead: stored_only_mapping,
          lb: stored_only_mapping,
          position_in_juan: stored_only_mapping,
          file: stored_only_mapping,
          vol: stored_only_mapping,
          juan: { type: 'integer', index: false, doc_values: false }
        }
      }
    end
  end
end
