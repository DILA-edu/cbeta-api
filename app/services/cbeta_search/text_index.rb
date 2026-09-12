module CbetaSearch
  # CBETA 全文 (text) index。匯入來源是 rake search_xml:x2t 產出的 text.xml。
  #
  # 共用的 analyzer、similarity、匯入與 alias 切換見 IndexBase。
  class TextIndex < IndexBase
    # text.xml 平均每卷約 60KB、兩個 content 欄位，200 卷約 24MB，
    # 遠低於 ES 預設的 http.max_content_length (100MB)。
    DEFAULT_BATCH_SIZE = 200

    SOURCE_FIELDS = %w[
      canon canon_order category category_ids creator_id file vol work
      title byline creators creators_with_id dynasty
      time_from time_to juan juan_start juan_list work_type alt
    ].freeze

    # 舊 API 可用的排序欄位見 static_pages/search.haml。
    SORT_FIELDS = {
      'canon' => 'canon_order',
      'canon_order' => 'canon_order',
      'category' => 'category',
      'file' => 'file',
      'vol' => 'vol',
      'work' => 'work',
      'juan' => 'juan',
      'work_type' => 'work_type',
      'dynasty' => 'dynasty',
      'time_dynasty' => 'dynasty',
      'time_from' => 'time_from',
      'time_to' => 'time_to',
      'title' => 'title.keyword',
      'byline' => 'byline.keyword',
      'creators' => 'creators.keyword',
      'creators_with_id' => 'creators_with_id.keyword'
    }.freeze

    # all_in_one 的預設排序
    DEFAULT_SORT = [
      { 'canon_order' => { 'order' => 'asc' } },
      { 'work' => { 'order' => 'asc' } },
      { 'juan' => { 'order' => 'asc' } }
    ].freeze

    # 舊版 Manticore 在平手時是回傳內部 doc id 的順序 (不可預期，例如同一部典籍的
    # 卷 3 會排在卷 1 前面)，這裡改成穩定且語意合理的順序，讓分頁結果可預期。
    TIEBREAKER = %w[canon_order work juan].freeze

    # 對應舊 SearchController#init_fields 的欄位與順序。
    # vol / work_type 舊版不回傳，供呼叫端內部使用 (輸出前由 fields 參數過濾掉)。
    ROW_FIELDS = {
      canon: 'canon',
      category: 'category',
      file: 'file',
      work: 'work',
      juan: 'juan',
      title: 'title',
      byline: 'byline',
      creators: 'creators',
      creators_with_id: 'creators_with_id',
      time_dynasty: 'dynasty',
      time_from: 'time_from',
      time_to: 'time_to',
      juan_list: 'juan_list',
      vol: 'vol',
      work_type: 'work_type'
    }.freeze

    class << self
      def key = :text
      def integer_fields = %w[juan juan_start time_from time_to].freeze
      def array_integer_fields = %w[category_ids creator_id].freeze
      def source_fields = SOURCE_FIELDS
      def sort_fields = SORT_FIELDS
      def default_sort = DEFAULT_SORT
      def tiebreaker = TIEBREAKER
      def row_fields = ROW_FIELDS
      def row_term_hits? = true
      # text 是一卷一份 document，work + juan 唯一
      def exclude_pushdown? = true
    end

    def mappings
      {
        # content 全文不需要回傳(顯示端走 KwicService)，排除以節省 _source 空間。
        # 這與 Manticore 現況一致(text.conf 用 xmlpipe_field，不存原文)。
        # term_freq 計分走倒排索引，不受此影響。
        _source: { excludes: %w[content content_without_notes] },
        properties: {
          content: term_freq_field,
          content_without_notes: term_freq_field,
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
    end
  end
end
