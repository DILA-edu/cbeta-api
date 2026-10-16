require 'test_helper'

# ImportToc、ImportLines 定義在 lib/tasks/import/*.rake 裡,
# 透過 load_tasks 載入 rake 檔即可取得 class 常數。
Rails.application.load_tasks unless defined?(ImportToc) && defined?(ImportLines)

# 只匯入部分藏經時, 不可動到其他藏經的資料。
class ImportPartialTest < ActiveSupport::TestCase
  test 'import:toc[G] 不會刪掉 GA、GB 的目次' do
    TocNode.create!(canon: 'G', work: 'G1977', n: 'G1977.old', label: 'G 舊')
    TocNode.create!(canon: 'GA', work: 'GA0002', n: 'GA0002.1', label: 'GA')
    TocNode.create!(canon: 'GB', work: 'GB0109', n: 'GB0109.1', label: 'GB')

    importer = ImportToc.new
    # 不讀 XML, 直接模擬匯入 G 的結果
    importer.define_singleton_method(:import_canon) do |canon|
      @inserts << { canon:, work: 'G1977', n: 'G1977.new', label: 'G 新' }
    end
    capture_io { importer.import('G') }

    assert_equal %w[G1977.new], TocNode.where(canon: 'G').pluck(:n)
    assert_equal 1, TocNode.where(canon: 'GA').count
    assert_equal 1, TocNode.where(canon: 'GB').count
  end

  test 'import:lines 帶參數時中止, 不刪也不重匯' do
    importer = ImportLines.allocate # 不需要讀 XML 與缺字資料
    count = Line.count

    _out, err = capture_io do
      assert_raises(SystemExit) { importer.import('T') }
    end

    assert_match(/不支援只匯入部分/, err)
    assert_equal count, Line.count
  end

  # label_path 依實際走訪的樹算出, 不以 n 反查 parent
  test 'import:toc 走訪時算出每個節點的 label_path' do
    importer = ImportToc.allocate
    importer.instance_variable_set(:@work, 'T0001')
    importer.instance_variable_set(:@inserts, [])
    importer.instance_variable_set(:@toc_stack, [ 0 ])
    importer.instance_variable_set(:@label_stack, [])

    # 第三個節點跳了一層 (level 1 之後直接 level 3), 依 n 的規則仍算 A 的子節點
    [ [ 1, 'A' ], [ 2, 'A1' ], [ 3, 'A1a' ], [ 2, 'A2' ], [ 1, 'B' ], [ 3, 'B1' ] ].each do |level, label|
      node = Nokogiri::XML(%(<mulu level="#{level}">#{label}</mulu>)).root
      importer.send(:handle_mulu, node)
    end

    rows = importer.instance_variable_get(:@inserts).map { it.values_at(:n, :parent, :label_path) }
    assert_equal [
      [ 'T0001.1', 'T0001.', 'A' ],
      [ 'T0001.1.1', 'T0001.1', 'A/A1' ],
      [ 'T0001.1.1.1', 'T0001.1.1', 'A/A1/A1a' ],
      [ 'T0001.1.2', 'T0001.1', 'A/A2' ],
      [ 'T0001.2', 'T0001.', 'B' ],
      [ 'T0001.2.1', 'T0001.2', 'B/B1' ]
    ], rows
  end
end
