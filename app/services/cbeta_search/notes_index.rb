module CbetaSearch
  # 校勘條目、註解、夾注 (notes) index。
  # 匯入來源是 rake manticore:notes 產出的 notes.xml。
  class NotesIndex < IndexBase
    # notes 每筆平均約 600 bytes，2,000 筆一批約 1.2MB。
    DEFAULT_BATCH_SIZE = 2_000

    # 對應舊 SearchController#init_notes 的欄位清單，再加上 filter / 排序要用的欄位。
    SOURCE_FIELDS = %w[
      note_place canon canon_order category category_ids creator_id vol file
      work title juan lb n content content_w_puncs prefix suffix
      dynasty time_from time_to creators creators_with_id
    ].freeze

    SORT_FIELDS = {
      'canon' => 'canon_order',
      'canon_order' => 'canon_order',
      'category' => 'category',
      'file' => 'file',
      'vol' => 'vol',
      'work' => 'work',
      'juan' => 'juan',
      'lb' => 'lb',
      'note_place' => 'note_place',
      'dynasty' => 'dynasty',
      'time_dynasty' => 'dynasty',
      'time_from' => 'time_from',
      'time_to' => 'time_to',
      'title' => 'title.keyword',
      'creators' => 'creators.keyword',
      'creators_with_id' => 'creators_with_id.keyword'
    }.freeze

    # 對應舊 init_order 的 "ORDER BY canon_order ASC, vol ASC, lb ASC"
    DEFAULT_SORT = [
      { 'canon_order' => { 'order' => 'asc' } },
      { 'vol' => { 'order' => 'asc' } },
      { 'lb' => { 'order' => 'asc' } }
    ].freeze

    # 同一行可能有多條註解，再以 work / juan / n 決定順序，讓分頁結果可預期。
    TIEBREAKER = %w[canon_order vol lb work juan].freeze

    # 對應舊 SearchController#init_notes 的 @fields 與順序。
    # content_w_puncs / prefix / suffix 只給 notes_highlight 用，輸出前會被刪掉。
    ROW_FIELDS = {
      note_place: 'note_place',
      canon: 'canon',
      category: 'category',
      vol: 'vol',
      file: 'file',
      work: 'work',
      title: 'title',
      juan: 'juan',
      lb: 'lb',
      n: 'n',
      content: 'content',
      content_w_puncs: 'content_w_puncs',
      prefix: 'prefix',
      suffix: 'suffix'
    }.freeze

    class << self
      def key = :notes
      def integer_fields = %w[juan time_from time_to].freeze
      def array_integer_fields = %w[category_ids creator_id].freeze
      def source_fields = SOURCE_FIELDS
      def sort_fields = SORT_FIELDS
      def default_sort = DEFAULT_SORT
      def tiebreaker = TIEBREAKER
      def row_fields = ROW_FIELDS
    end

    def mappings
      {
        properties: {
          # 唯一被搜尋的欄位 (去標點版)，對應 notes.conf 的 xmlpipe_field_string = content。
          content: term_freq_field,

          # 只回傳、不搜尋: 在 Manticore 是 string attribute，本來就不進 index。
          content_w_puncs: stored_only_mapping,
          prefix: stored_only_mapping,
          suffix: stored_only_mapping,
          n: stored_only_mapping,

          note_place: keyword_mapping,
          canon: keyword_mapping,
          canon_order: keyword_mapping,
          category: keyword_mapping,
          vol: keyword_mapping,
          file: keyword_mapping,
          work: keyword_mapping,
          lb: keyword_mapping,
          dynasty: keyword_mapping,
          title: text_and_keyword_mapping,
          creators: text_and_keyword_mapping,
          creators_with_id: text_and_keyword_mapping,
          category_ids: { type: 'integer' },
          creator_id: { type: 'integer' },
          juan: { type: 'integer' },
          time_from: { type: 'integer' },
          time_to: { type: 'integer' }
        }
      }
    end
  end
end
