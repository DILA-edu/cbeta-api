require 'test_helper'

# ImportWorkInfo 定義在 lib/tasks/import/work_info.rake 裡,
# 透過 load_tasks 載入 rake 檔即可取得 class 常數。
Rails.application.load_tasks unless defined?(ImportWorkInfo)

# import:work_info 清空並重建 works 相關資料表的部分。
# 讀 authority 與 XML 的兩段以假的取代, 只驗證清空、rollback 與 join table。
class ImportWorkInfoTest < ActiveSupport::TestCase
  setup do
    @old_place = Place.create!(auth_id: 'PL000000000001', name: '舊地名')
    Work.find_by!(n: 'T0001').places << @old_place
    @importer = ImportWorkInfo.allocate # 不讀 authority 與 XML
  end

  def pw_count = ActiveRecord::Base.connection.select_value('SELECT count(*) FROM places_works')

  test '重新匯入時清掉 places_works, 不留下指向已刪除 place 的列' do
    @importer.define_singleton_method(:import_from_authority) do
      Work.find_by!(n: 'T0001').places << Place.create!(auth_id: 'PL000000000002', name: '新地名')
    end
    @importer.define_singleton_method(:import_from_xml) { nil }

    ActiveRecord::Base.transaction { @importer.send(:replace_tables) }

    assert_equal 1, pw_count
    assert_equal %w[新地名], Work.find_by!(n: 'T0001').places.map(&:name)
  end

  test '匯入中途 abort 時整個 rollback, 舊資料保持完整' do
    xml_files = XmlFile.count
    @importer.define_singleton_method(:import_from_authority) { nil }
    @importer.define_singleton_method(:import_from_xml) { abort 'G2352 在 Work 裡找不到' }

    capture_io do
      assert_raises(SystemExit) { ActiveRecord::Base.transaction { @importer.send(:replace_tables) } }
    end

    assert_equal xml_files, XmlFile.count
    assert Place.exists?(@old_place.id)
    assert_equal 1, pw_count
  end
end
