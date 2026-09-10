module CbetaSearch
  # 佛典題名 (titles) index。匯入來源是 rake search_xml:titles 產出的 titles.xml。
  #
  # 與其他 index 不同，這裡要的是「相關度」而不是「出現次數」，
  # 因此 content 主欄位掛預設的 BM25。
  class TitlesIndex < IndexBase
    # 只有 4,887 筆、每筆很短，一次送完也無妨，仍分批以免 request 過大。
    DEFAULT_BATCH_SIZE = 2_000

    # search#title 的 quorum 門檻: 至少要有 3 個字符合。
    # 實測 /dev: q 只有 1~2 字時 Manticore 退化成「全部都要命中」而不是回 0 筆，
    # 因此門檻要取 [QUORUM_THRESHOLD, token 數].min。
    QUORUM_THRESHOLD = 3

    # variants 的 scope=title 計數用的 sub-field，掛 term_freq similarity。
    FREQ_SUBFIELD = 'content.freq'.freeze

    SOURCE_FIELDS = %w[
      work content canon canon_order category category_ids creator_id
      dynasty creators creators_with_id time_from time_to
    ].freeze

    SORT_FIELDS = {
      'canon' => 'canon_order',
      'canon_order' => 'canon_order',
      'work' => 'work',
      'category' => 'category',
      'dynasty' => 'dynasty',
      'time_dynasty' => 'dynasty',
      'time_from' => 'time_from',
      'time_to' => 'time_to'
    }.freeze

    # 舊版沒有 ORDER BY，靠 Manticore 預設的 proximity_bm25 相關度排序。
    DEFAULT_SORT = [{ '_score' => { 'order' => 'desc' } }].freeze

    # titles index 沒有 juan 欄位，tiebreaker 只到 work。
    TIEBREAKER = %w[canon_order work].freeze

    # 舊版 SELECT 只取 work, content; 其餘欄位由 controller 從 Work model 補上。
    ROW_FIELDS = { work: 'work', content: 'content' }.freeze

    class << self
      def key = :titles
      def integer_fields = %w[time_from time_to].freeze
      def array_integer_fields = %w[category_ids creator_id].freeze
      def source_fields = SOURCE_FIELDS
      def sort_fields = SORT_FIELDS
      def default_sort = DEFAULT_SORT
      def tiebreaker = TIEBREAKER
      def row_fields = ROW_FIELDS
      def row_id? = false
    end

    def mappings
      {
        properties: {
          # 主欄位用預設 BM25: search#title 要的是相關度。
          # freq sub-field 掛 term_freq，給 variants 的 scope=title 計「出現次數」用
          # (舊版是 SUM(weight()) with ranker=wordcount)。
          content: {
            type: 'text',
            analyzer: ANALYZER,
            fields: {
              freq: {
                type: 'text',
                analyzer: ANALYZER,
                similarity: TERM_FREQ_SIMILARITY,
                # 見 IndexBase#term_freq_field 的說明
                norms: false
              },
              keyword: { type: 'keyword', ignore_above: 512 }
            }
          },
          work: keyword_mapping,
          canon: keyword_mapping,
          canon_order: keyword_mapping,
          category: keyword_mapping,
          dynasty: keyword_mapping,
          creators: text_and_keyword_mapping,
          creators_with_id: text_and_keyword_mapping,
          category_ids: { type: 'integer' },
          creator_id: { type: 'integer' },
          time_from: { type: 'integer' },
          time_to: { type: 'integer' }
        }
      }
    end
  end
end
