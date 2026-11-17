require 'test_helper'

# 四個 index 的 mapping 與欄位設定。
# analyzer 與 similarity 的行為測試在 text_index_test.rb（四個 index 共用同一套）。
class CbetaSearch::IndexDefinitionsTest < ActiveSupport::TestCase
  INDEXES = [CbetaSearch::TextIndex, CbetaSearch::NotesIndex,
             CbetaSearch::TitlesIndex, CbetaSearch::ChunksIndex].freeze

  test '四個 index 共用同一套 analyzer 與 tokenizer' do
    # 舊 Manticore 四個 index 的 charset_table / ngram 設定逐字相同，
    # 所以 ES 這邊也必須一致，否則同一個查詢在不同 index 會切出不同的詞。
    settings = INDEXES.map { |k| k.new.index_body[:settings][:analysis] }

    assert_equal 1, settings.uniq.size
  end

  test 'alias 由 text 的 alias 推導，四個各不相同' do
    aliases = INDEXES.map(&:index_alias)

    assert_equal aliases.uniq.size, aliases.size, "alias 重複會讓不同 index 互相覆蓋：#{aliases}"
  end

  test '每個 index 的 row_fields 都在 source_fields 裡' do
    INDEXES.each do |klass|
      missing = klass.row_fields.values - klass.source_fields
      assert_empty missing, "#{klass}: row_fields 有欄位不在 source_fields，會回傳 nil：#{missing}"
    end
  end

  test '每個 index 的 sort_fields 與 tiebreaker 都對應到 mapping 有的欄位' do
    INDEXES.each do |klass|
      properties = klass.new.mappings[:properties]
      targets = klass.sort_fields.values + klass.tiebreaker
      targets.each do |field|
        next if field.start_with?('_') # _doc / _score 是 ES 的內建排序欄位

        root = field.split('.').first
        assert properties.key?(root.to_sym),
               "#{klass}: 排序欄位 #{field} 不在 mapping 裡，ES 會排不出來"
      end
    end
  end

  test 'notes: 只有 content 進倒排索引，其餘長文字欄位只回傳不搜尋' do
    properties = CbetaSearch::NotesIndex.new.mappings[:properties]

    assert_equal CbetaSearch::IndexBase::TERM_FREQ_SIMILARITY, properties[:content][:similarity]
    %i[content_w_puncs prefix suffix n].each do |field|
      assert_equal false, properties[field][:index], "#{field} 不該建倒排索引"
    end
  end

  test 'titles: content 用 BM25, freq sub-field 才是 term_freq' do
    properties = CbetaSearch::TitlesIndex.new.mappings[:properties]

    # 主欄位不掛 term_freq: search#title 要的是相關度
    assert_nil properties[:content][:similarity]
    # variants 的 scope=title 要算出現次數，走 freq sub-field
    assert_equal CbetaSearch::IndexBase::TERM_FREQ_SIMILARITY,
                 properties[:content][:fields][:freq][:similarity]
    assert_equal 'content.freq', CbetaSearch::TitlesIndex::FREQ_SUBFIELD
  end

  test 'chunks: content 用 BM25, Smith-Waterman 要的全文必須在 _source 裡' do
    properties = CbetaSearch::ChunksIndex.new.mappings[:properties]

    # 第一階段要的是相關度，不是出現次數，所以不掛 term_freq、也不關 norms
    assert_nil properties[:content][:similarity]
    assert_nil properties[:content][:norms]
    assert_includes CbetaSearch::ChunksIndex.source_fields, 'content'

    # 4 百多萬筆，只有 filter 會用到的欄位才建索引
    %i[category title creators creators_with_id linehead lb position_in_juan file vol juan]
      .each do |field|
      assert_equal false, properties[field][:index], "#{field} 不該建倒排索引"
    end
  end

  # 舊版 SELECT 沒有取 position_in_juan，similar_smith_waterman 的
  # 「卷首／卷尾除外」因此永遠不成立。改用 ES 時一併修正。
  test 'chunks: position_in_juan 要進 row_fields，卷首／卷尾判斷才有依據' do
    assert_includes CbetaSearch::ChunksIndex.row_fields.keys, :position_in_juan
  end

  test 'notes / titles / chunks 沒有 content_without_notes，note=0 不能套用' do
    [CbetaSearch::NotesIndex, CbetaSearch::TitlesIndex, CbetaSearch::ChunksIndex].each do |klass|
      refute klass.new.mappings[:properties].key?(:content_without_notes),
             "#{klass} 若有這個欄位，SearchController 的 @text_field 判斷要一併改"
    end
  end

  # alias 的推導規則決定了 staging 與 production 會不會撞在一起
  # （兩者是同一台機器、同一個 ES 服務，只靠 alias 隔離）。
  test 'CbetaEsAlias: 由 text alias 推導其他 index 的 alias' do
    assert_equal({ text: 'cbeta_text_current',
                   notes: 'cbeta_notes_current',
                   titles: 'cbeta_titles_current',
                   chunks: 'cbeta_chunks_current' },
                 CbetaEsAlias.build('cbeta_text_current'))

    assert_equal 'cbeta_notes_staging', CbetaEsAlias.build('cbeta_text_staging')[:notes]
  end

  test 'CbetaEsAlias: 不含 text 的名稱直接加後綴' do
    assert_equal 'my_index_notes', CbetaEsAlias.build('my_index')[:notes]
  end

  test 'CbetaEsAlias: cb.yml 可以逐一覆寫' do
    aliases = CbetaEsAlias.build('cbeta_text_current', { notes: 'another_notes' })

    assert_equal 'another_notes', aliases[:notes]
    assert_equal 'cbeta_titles_current', aliases[:titles]
  end

  STAGING_NOTES = Class.new(CbetaSearch::NotesIndex) do
    def self.index_alias = 'cbeta_notes_staging'
  end

  # 名稱不帶角色：staging 建的 index 上線時 production 直接 promote 過去用
  test 'versioned_index_name: production 與 staging 推導出同一個名稱' do
    assert_equal 'cbeta_notes_2026r3_001',
                 CbetaSearch::NotesIndex.versioned_index_name('2026R3')
    assert_equal 'cbeta_notes_2026r3_003', STAGING_NOTES.versioned_index_name('2026R3', '003')
  end

  test 'versioned_index_name: 其他 alias 名稱只去掉 _current / _staging' do
    test_notes = Class.new(CbetaSearch::NotesIndex) do
      def self.index_alias = 'cbeta_notes_test'
    end

    assert_equal 'cbeta_notes_test_2026r3_001', test_notes.versioned_index_name('2026R3')
  end

  test 'rebuild_blockers: 只被自己 (staging) 指著的 index 可以原地重建' do
    assert_empty STAGING_NOTES.rebuild_blockers([])
    assert_empty STAGING_NOTES.rebuild_blockers(%w[cbeta_notes_staging])
  end

  test 'rebuild_blockers: production 在用的 index 不准重建' do
    assert_equal %w[cbeta_notes_current],
                 STAGING_NOTES.rebuild_blockers(%w[cbeta_notes_staging cbeta_notes_current])
    assert_equal %w[cbeta_notes_current],
                 CbetaSearch::NotesIndex.rebuild_blockers(%w[cbeta_notes_current])
  end

  test 'rebuild_blockers: production 不准重建 staging 在用的 index' do
    assert_equal %w[cbeta_notes_staging],
                 CbetaSearch::NotesIndex.rebuild_blockers(%w[cbeta_notes_staging])
  end

  test 'versioned_index_name: 名稱不可以等於 alias（ES 會拒絕）' do
    INDEXES.each do |klass|
      refute_equal klass.index_alias, klass.versioned_index_name('2026R3')
    end
  end
end
