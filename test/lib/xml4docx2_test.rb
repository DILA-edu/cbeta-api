require 'test_helper'

# `XMLForDocx2` 定義在 lib/tasks/convert/xml4docx2.rake 裡,
# 透過 load_tasks 載入 rake 檔即可取得該 class 常數。
Rails.application.load_tasks unless defined?(XMLForDocx2)

# 迴歸測試:xml4docx 小字夾注的前後小括號。
#
# 背景:
#   xml4docx1 把 CBETA XML 的夾注轉成 <p>,再由 xml4docx2 的 e_p
#   依 inlinenote? 判斷,在段落文字前後補上小括號。
#
# Bug:
#   夾注有兩種來源,rend 命名不同:
#     1. <note place="inline">  → rend 含 inlinenote (ex: inlinenote_lg)
#     2. <lg subtype="note1|note2"> → rend 為 lg_note1 / lg_note2
#   舊版 inlinenote? 只比對字串是否含 "inlinenote",
#   第 2 種(ex: X09n0243_p0343b16、X18n0332_p0067b20)因此漏掉小括號。
class XMLForDocx2Test < ActiveSupport::TestCase
  # rend 為 lg 加上 note1/note2 的,都算小字夾注。
  # lg_note1_m2 是外層 <p style="margin-left:2em"> 包 lg 時,
  # 由 handle_p_contain_p 合併 rend 而成 (ex: X57n0980_p0779a14)。
  INLINE_NOTE_RENDS = %w[
    inlinenote
    inlinenote_lg
    inlinenote_p
    lg_note1
    lg_note2
    lg_note1_m2
  ].freeze

  # 一般段落樣式,不該被加小括號。
  PLAIN_RENDS = %w[lg lg_small m1 m2 head juan byline].freeze

  test "inlinenote? 認得 lg_note1 / lg_note2 等 lg 夾注" do
    INLINE_NOTE_RENDS.each do |rend|
      assert inlinenote?(%(<p rend="#{rend}">文</p>)),
             %(rend="#{rend}" 應被視為小字夾注)
    end
  end

  test "inlinenote? 不把一般段落樣式當成夾注" do
    PLAIN_RENDS.each do |rend|
      assert_not inlinenote?(%(<p rend="#{rend}">文</p>)),
                 %(rend="#{rend}" 不該被視為小字夾注)
    end

    assert_not inlinenote?('<p>文</p>'), '沒有 rend 的 p 不該被視為夾注'
    assert_not inlinenote?(%(<seg rend="inlinenote">文</seg>)),
               'seg 不是 p,不該被 inlinenote? 認可'
  end

  test "e_p 在 lg_note1 / lg_note2 段落前後補上小括號" do
    # X18n0332_p0067b20 <lg subtype="note2">
    xml = <<~XML
      <p rend="lg_note2"><!-- lb: X18n0332_p0067b20 -->筆底楞伽一字無，　　浮雲散去月明孤。<lb/>恩深欲報辭難盡，　　塵劫分身舌不枯。</p>
    XML

    p_node = run_e_p(xml)
    assert_equal '(筆底楞伽一字無，　　浮雲散去月明孤。恩深欲報辭難盡，　　塵劫分身舌不枯。)',
                 p_node.text
    # 註解 (行號) 要保留
    assert_includes p_node.inner_html, '<!-- lb: X18n0332_p0067b20 -->'
  end

  test "e_p 在 lg 與 margin 合併的 lg_note1_m2 段落也補上小括號" do
    # X57n0980_p0779a14 <p style="margin-left:2em"> 包 <lg subtype="note1">
    xml = %(<p rend="lg_note1_m2">身攝邊見戒攝取，　　邪見元從疑惑生，</p>)

    assert_equal '(身攝邊見戒攝取，　　邪見元從疑惑生，)', run_e_p(xml).text
  end

  test "e_p 不動一般 lg 段落" do
    xml = %(<p rend="lg">世間五欲樂，　　或復諸天樂；</p>)

    assert_equal '世間五欲樂，　　或復諸天樂；', run_e_p(xml).text
  end

  test "e_p 不重複加小括號" do
    xml = %(<p rend="lg_note2">(筆底楞伽一字無，)</p>)

    assert_equal '(筆底楞伽一字無，)', run_e_p(xml).text
  end

  private

  def converter
    obj = XMLForDocx2.new
    obj.instance_variable_set(:@log, File.open(File::NULL, 'w'))
    obj.instance_variable_set(:@xml_fn, 'test.xml')
    obj.instance_variable_set(:@work, 'test')
    obj
  end

  def inlinenote?(xml)
    node = Nokogiri::XML("<root>#{xml}</root>").root.elements.first
    converter.send(:inlinenote?, node)
  end

  # 跑一次 e_p,回傳處理後的 p node。
  def run_e_p(xml)
    doc = Nokogiri::XML("<root>#{xml}</root>")
    p_node = doc.at_xpath('//p')
    converter.send(:e_p, p_node)
    doc.at_xpath('//p')
  end
end
