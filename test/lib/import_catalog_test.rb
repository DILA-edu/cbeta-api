require 'test_helper'

# `ImportCatalog` 定義在 lib/tasks/import/catalog.rake 裡,
# 透過 load_tasks 載入 rake 檔即可取得該 class 常數。
Rails.application.load_tasks unless defined?(ImportCatalog)

# advance_nav.txt 有一種節點格式是「cbeta 行首資訊 + 標題」, 例如:
#   T09n0262_p0056c02 T0262 (卷7) 妙法蓮華經觀世音菩薩普門品
#
# 行首資訊要交給 GotoService 解析, 把 work / file / juan / lb
# 填進 CatalogEntry。
class ImportCatalogTest < ActiveSupport::TestCase
  setup do
    @importer = ImportCatalog.new
    @importer.instance_variable_set(:@log, StringIO.new)
  end

  test "LINEHEAD_REGEX 只吃行首資訊格式" do
    assert_match ImportCatalog::LINEHEAD_REGEX, "T09n0262_p0056c02"
    assert_no_match ImportCatalog::LINEHEAD_REGEX, "T0262"       # 一般典籍編號
    assert_no_match ImportCatalog::LINEHEAD_REGEX, "T0220_576"   # 卷號節點
    assert_no_match ImportCatalog::LINEHEAD_REGEX, "bulei.html"
  end

  test "行首資訊節點填入 CatalogEntry 各欄位" do
    node = build_node("T09n0262_p0056c02 T0262 (卷7) 妙法蓮華經觀世音菩薩普門品")

    @importer.send(:handle_linehead_node, "orig-T.001", node: node, start: 3)

    entry = CatalogEntry.last
    assert_equal "orig-T.001.003", entry.n
    assert_equal "T0262 (卷7) 妙法蓮華經觀世音菩薩普門品", entry.label
    assert_equal "work", entry.node_type
    assert_equal "T0262", entry.work
    assert_equal "T09n0262", entry.file
    assert_equal "0056c02", entry.lb
    assert_equal 7, entry.juan_start
    assert_equal 7, entry.juan_end
    assert_equal 3, entry.sort
  end

  test "卷號範圍節點填入起訖卷與 node_type" do
    node = build_node("T0220_001..400 T0220 (卷1-400) 大般若波羅蜜多經第1會")

    @importer.send(:handle_juan_node, "CBETA.003.001", node: node, start: 1)

    entry = CatalogEntry.last
    assert_equal "T0220 (卷1-400) 大般若波羅蜜多經第1會", entry.label
    assert_equal "work", entry.node_type
    assert_equal "T0220", entry.work
    assert_equal 1, entry.juan_start
    assert_equal 400, entry.juan_end
  end

  test "單卷節點的起訖卷相同" do
    node = build_node("T0220_576 T0220 (卷576) 大般若波羅蜜多經第8會那伽室利分")

    @importer.send(:handle_juan_node, "CBETA.003.008", node: node, start: 1)

    entry = CatalogEntry.last
    assert_equal 576, entry.juan_start
    assert_equal 576, entry.juan_end
  end

  test "行首資訊在 CBETA 裡找不到就中止匯入" do
    node = build_node("T09n0262_p9999a01 T0262 不存在的行")

    e = assert_raises(RuntimeError) do
      @importer.send(:handle_linehead_node, "orig-T.001", node: node, start: 1)
    end
    assert_match "T09n0262_p9999a01", e.message
    assert_equal 0, CatalogEntry.count
  end

  private

  def build_node(text)
    Nokogiri::XML(%(<root><node text="#{text}"/></root>)).at_xpath("//node")
  end
end
