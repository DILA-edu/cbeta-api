require 'test_helper'

# `ImportLayers` 定義在 lib/tasks/import/layers.rake 裡,
# 透過 load_tasks 載入 rake 檔即可取得該 class 常數。
Rails.application.load_tasks unless defined?(ImportLayers)

# 迴歸測試:layers 匯入時人名 anchor 的字位計算。
#
# 背景:
#   rake 'import:layers[GA079n0081]' 會依 CSV
#   (data-static/layers/fosizhi/GA/GA079/GA079n0081.csv) 在 HTML 插入
#   a.person_start / a.person_end 標示人名起迄。
#
# Bug:
#   CSV 第 25 字位是人名「夢覺」的「夢」:
#     0054a10,25,person,start,A009490,夢覺
#   但 GA079n0081_p0054a10 該行 span 文字含「全形空格　」,
#   而 CBETA 字位編號(span 的 w 屬性)不計入 PUNCS(標點與空格)。
#
#   span.t 字位分布:
#     w=15  不須求羽化　際此是登仙   → 字位 15..24 (仙=24,全形空格不計)
#     w=25  夢覺詩：                → 字位 25..27 (夢=25)
#
#   `import_row_text` 用 `text.size` 計算長度,把全形空格也算進去,
#   於是誤判第 25 字位落在 w=15 這個 span,把 anchor 插在「登」與「仙」之間,
#   而不是正確地跳到 w=25、插在「夢」之前。
class ImportLayersTest < ActiveSupport::TestCase
  # 重現該行的 HTML 結構(含全形空格),只保留關鍵的兩個 span.t。
  LINE_HTML = <<~HTML.freeze
    <div>
      <span class="lb" id="GA079n0081_p0054a10">GA079n0081_p0054a10</span>
      <span class="t" l="0054a10" w="15">不須求羽化　際此是登仙</span>
      <span class="t" l="0054a10" w="25">夢覺詩：</span>
    </div>
  HTML

  test "person_start anchor 應插在「夢」之前,不受同行全形空格影響" do
    doc = Nokogiri::HTML(LINE_HTML)

    row = {
      'lb'       => '0054a10',
      'position' => '25',
      'tag'      => 'person',
      'type'     => 'start',
      'key'      => 'A009490',
      'name'     => '夢覺'
    }
    anchor_html = %(<a id="person_start_352" class="person_start" data-key="A009490"/>)

    # 供 check_text 驗證用的整行文字(去 PUNCS)。前段補到字位 1..14。
    cbeta_line = '澗落寒泉四望山川盡平臨星斗懸' + '不須求羽化際此是登仙夢覺詩'
    insert_layer_anchor(doc, row, anchor_html, cbeta_line)

    anchor = doc.at_xpath('//a[@id="person_start_352"]')
    assert_not_nil anchor, 'anchor 應被插入'

    # 正確行為:anchor 應落在 w=25 的 span,且緊接在「夢」之前。
    assert_equal '25', anchor.parent['w'],
                 "anchor 應在 w=25 的 span,實際在 w=#{anchor.parent['w']}"
    assert_equal '夢', anchor.next.text[0],
                 "anchor 之後應緊接「夢」,實際為「#{anchor.next&.text&.slice(0)}」"
  end

  # 重現含缺字(gaijiAnchor)的行:缺字顯示為組字式(多字元),
  # 但在字位系統裡只佔一個字位。
  #   字位: 甲=1, 缺字=2, 乙=3, 丙=4
  GAIJI_HTML = <<~HTML.freeze
    <div>
      <span class="lb" id="TEST_p0001a01">TEST_p0001a01</span>
      <span class="t" l="0001a01" w="1">甲<a class="gaijiAnchor" href="#">⿰虫童</a>乙丙</span>
    </div>
  HTML

  test "gaijiAnchor 只佔一個字位,後續字位不因缺字顯示長度而偏移" do
    doc = Nokogiri::HTML(GAIJI_HTML)

    row = {
      'lb'       => '0001a01',
      'position' => '3',       # 目標為「乙」(字位 3),在缺字之後
      'tag'      => 'person',
      'type'     => 'start',
      'key'      => 'A000001',
      'name'     => '乙'
    }
    anchor_html = %(<a id="person_start_1" class="person_start" data-key="A000001"/>)

    # 缺字在整行文字裡以一個字代表(此處用 ◇)。字位: 甲=1, ◇=2, 乙=3, 丙=4
    insert_layer_anchor(doc, row, anchor_html, '甲◇乙丙')

    anchor = doc.at_xpath('//a[@id="person_start_1"]')
    assert_not_nil anchor, 'anchor 應被插入'

    # 正確行為:anchor 應緊接在「乙」之前。
    # 舊版以缺字顯示長度(3 字元)計算,會把 anchor 誤插在缺字之前。
    assert_equal '乙', anchor.next.text[0],
                 "anchor 之後應緊接「乙」,實際為「#{anchor.next&.text&.slice(0)}」"
  end

  private

  # 以最小依賴驅動 `ImportLayers` 的節點走訪邏輯,
  # 模擬 `import_row` 針對某一 layer row 逐一 span.t 插入 anchor 的流程,
  # 但略過 DB / 檔案 / 外部 git repo 相依(用 allocate 跳過 initialize)。
  def insert_layer_anchor(doc, row, anchor_html, cbeta_line)
    obj = ImportLayers.allocate
    obj.instance_variable_set(:@vars, {})
    obj.instance_variable_set(:@mismatch, 0)
    obj.instance_variable_set(:@work, 'GA079n0081')
    obj.instance_variable_set(:@log_buf, { dirty: false, text: +'' })

    # check_text 會用整行(去 PUNCS)的文字驗證字位。
    obj.instance_variable_set(:@cbeta_lines, { row['lb'] => cbeta_line })

    obj.instance_variable_set(:@row, row)
    obj.instance_variable_set(:@layer_pos, row['position'].to_i)
    obj.instance_variable_set(:@line_text, +'')
    obj.instance_variable_set(:@anchor, anchor_html)

    start_lb = doc.at_xpath('//span[@class="lb"]')
    start_lb.xpath('./following::span[@class="t"]').each do |node|
      obj.instance_variable_set(:@html_pos, node['w'].to_i - 1)
      break if obj.send(:import_row_traverse, node)
    end
  end
end
