require 'test_helper'

# 三個 index 的 mapping 與欄位設定。
# analyzer 與 similarity 的行為測試在 text_index_test.rb（三個 index 共用同一套）。
class CbetaSearch::IndexDefinitionsTest < ActiveSupport::TestCase
  INDEXES = [CbetaSearch::TextIndex, CbetaSearch::NotesIndex, CbetaSearch::TitlesIndex].freeze

  test '三個 index 共用同一套 analyzer 與 tokenizer' do
    # 四個 manticore-template-*.conf 的 charset_table / ngram 設定逐字相同，
    # 所以 ES 這邊也必須一致，否則同一個查詢在不同 index 會切出不同的詞。
    settings = INDEXES.map { |k| k.new.index_body[:settings][:analysis] }

    assert_equal 1, settings.uniq.size
  end

  test 'alias 由 text 的 alias 推導，三個各不相同' do
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

  test 'notes / titles 沒有 content_without_notes，note=0 不能套用' do
    [CbetaSearch::NotesIndex, CbetaSearch::TitlesIndex].each do |klass|
      refute klass.new.mappings[:properties].key?(:content_without_notes),
             "#{klass} 若有這個欄位，SearchController 的 @text_field 判斷要一併改"
    end
  end

  # alias 的推導規則決定了 staging 與 production 會不會撞在一起
  # （兩者是同一台機器、同一個 ES 服務，只靠 alias 隔離）。
  test 'CbetaEsAlias: 由 text alias 推導其他 index 的 alias' do
    assert_equal({ text: 'cbeta_text_current',
                   notes: 'cbeta_notes_current',
                   titles: 'cbeta_titles_current' },
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

  # staging 與 production 是同一台機器、共用同一個 Elasticsearch，
  # index 名稱撞在一起會互相覆蓋。
  test 'versioned_index_name: production 與 staging 不會撞名' do
    assert_equal 'cbeta_notes_2026r3_001',
                 CbetaSearch::NotesIndex.versioned_index_name('2026R3')

    staging = Class.new(CbetaSearch::NotesIndex) do
      def self.index_alias = 'cbeta_notes_staging'
    end

    assert_equal 'cbeta_notes_staging_2026r3_001', staging.versioned_index_name('2026R3')
  end

  test 'versioned_index_name: 名稱不可以等於 alias（ES 會拒絕）' do
    INDEXES.each do |klass|
      refute_equal klass.index_alias, klass.versioned_index_name('2026R3')
    end
  end
end
