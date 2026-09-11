require 'test_helper'

# search/variants 的異體字展開。
#
# 這條路徑原本是每產生一個候選字串就問一次「CBETA 有沒有用到」，而每次都可能
# 要循序查三個 index，六字查詢因此送出上百個 HTTP 請求。改成整層批次 (_msearch)
# 之後，短路語意與展開結果都必須和逐一問的版本一模一樣。
class SearchControllerVariantsTest < ActiveSupport::TestCase
  # 記錄每次被問到的詞組，好斷言「問了幾次、問了哪些」。
  class FakeIndexService
    attr_reader :calls

    def initialize(known)
      @known = known
      @calls = []
    end

    def exist_all?(phrases, **)
      @calls << phrases.dup
      phrases.to_h { |phrase| [phrase, @known.include?(phrase)] }
    end
  end

  setup do
    @controller = SearchController.new
    @text = FakeIndexService.new([])
    @notes = FakeIndexService.new([])
    @titles = FakeIndexService.new([])
  end

  test '整批問, 每個 index 每層只問一次' do
    @text = FakeIndexService.new(%w[無上 旡上])
    stub_services

    r = filter(%w[無上 旡上 无上 無丄])

    assert_equal %w[無上 旡上], r
    assert_equal 1, @text.calls.size
    assert_equal %w[無上 旡上 无上 無丄], @text.calls.first
  end

  test 'text 命中的不再問 notes 與 titles' do
    @text = FakeIndexService.new(%w[無上])
    @notes = FakeIndexService.new(%w[无上])
    stub_services

    r = filter(%w[無上 无上 旡上])

    assert_equal %w[無上 无上], r
    assert_equal %w[无上 旡上], @notes.calls.first, 'text 命中的不該再問 notes'
    assert_equal %w[旡上], @titles.calls.first, 'notes 命中的不該再問 titles'
  end

  test '三個 index 都沒有就不算存在' do
    stub_services

    assert_empty filter(%w[無上 无上])
    assert_equal 1, @text.calls.size
    assert_equal 1, @notes.calls.size
    assert_equal 1, @titles.calls.size
  end

  test 'titles 只問長度小於 58 的詞組' do
    long = '佛' * 58
    stub_services

    filter([long, '無上'])

    assert_equal [long, '無上'], @text.calls.first
    assert_equal [long, '無上'], @notes.calls.first
    assert_equal %w[無上], @titles.calls.first, 'title 最長 57, 更長的不必問'
  end

  test '全部詞組都太長時, titles 完全不必問' do
    long = '佛' * 60
    stub_services

    assert_empty filter([long])
    assert_empty @titles.calls
  end

  test '空陣列不會發出任何請求' do
    stub_services

    assert_empty filter([])
    assert_empty @text.calls
  end

  test '結果保持傳入順序' do
    @text = FakeIndexService.new(%w[丙 甲 乙])
    stub_services

    assert_equal %w[甲 乙 丙], filter(%w[甲 乙 丙])
  end

  test 'expand_vars_array 逐層展開, 上一層存活的才往下組合' do
    @text = FakeIndexService.new(%w[無 旡 無上 旡上 無上正])
    stub_services

    r = @controller.send(:expand_vars_array, [%w[無 旡 无], %w[上 丄], %w[正]], true)

    assert_equal %w[無上正], r
    # 第一層 3 個、第二層 (無/旡)×(上/丄) 4 個、第三層 (無上/旡上)×正 2 個
    assert_equal [3, 4, 2], @text.calls.map(&:size)
  end

  test 'expand_vars_array 這一層全滅就不再往下找' do
    @text = FakeIndexService.new(%w[無])
    stub_services

    assert_empty @controller.send(:expand_vars_array, [%w[無], %w[上], %w[正]], true)
    assert_equal [1, 1], @text.calls.map(&:size), '第二層全滅, 不該再問第三層'
  end

  test 'expand_vars_array 的 chk_exist 為 false 時不查 Elasticsearch' do
    stub_services

    r = @controller.send(:expand_vars_array, [%w[無 旡], %w[上]], false)

    assert_equal %w[無上 旡上], r
    assert_empty @text.calls
  end

  private

  def filter(phrases)
    @controller.send(:filter_exist_in_cbeta, phrases)
  end

  def stub_services
    services = {
      CbetaSearch::TextIndex => @text,
      CbetaSearch::NotesIndex => @notes,
      CbetaSearch::TitlesIndex => @titles
    }
    @controller.define_singleton_method(:es_service) { |index| services.fetch(index) }
  end
end
