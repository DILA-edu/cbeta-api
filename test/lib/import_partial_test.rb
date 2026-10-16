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
end
