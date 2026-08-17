# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'zip'

# 鎖住 xml4docx 轉 odt 的 package 結構, 重點在 ODF 特有的規則:
# mimetype 不壓縮、automatic style、covered cell、manifest。
class XmlToOdtConverterTest < ActiveSupport::TestCase
  FIXTURES = Rails.root.join('test/fixtures/files')
  SAMPLE_XML = FIXTURES.join('xml4docx/sample.xml').to_s
  FIGURES = FIXTURES.join('figures').to_s

  test "mimetype 是第一個 entry 且不壓縮" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'out.odt')
      XmlToOdtConverter.new(SAMPLE_XML).convert(path)

      Zip::File.open(path) do |zip|
        first = zip.entries.first
        assert_equal 'mimetype', first.name
        assert_equal Zip::Entry::STORED, first.compression_method
        assert_equal XmlToOdtConverter::MIMETYPE, first.get_input_stream.read
      end
    end
  end

  test "圖片存進 Pictures 並登記在 manifest" do
    with_odt(SAMPLE_XML, figures_dir: FIGURES) do |odt, _warnings|
      # 同一張圖用了三次 (body 兩次 + footnote 一次), 只存一份
      assert_equal ['Pictures/image1.gif'], odt.keys.grep(%r{\APictures/})
      assert_equal File.binread(File.join(FIGURES, 'T/sample.gif')), odt['Pictures/image1.gif']

      assert_includes odt['META-INF/manifest.xml'],
                      '<manifest:file-entry manifest:full-path="Pictures/image1.gif" manifest:media-type="image/gif"/>'
      assert_equal 3, odt['content.xml'].scan('xlink:href="Pictures/image1.gif"').size
    end
  end

  test "圖片以 96 DPI 換算 cm" do
    with_odt(SAMPLE_XML, figures_dir: FIGURES) do |odt, _warnings|
      # sample.gif 是 44x35 px
      assert_includes odt['content.xml'], 'svg:width="1.164cm" svg:height="0.926cm"'
    end
  end

  test "超出版面的圖等比縮小" do
    Dir.mktmpdir do |figures|
      write_gif_header(File.join(figures, 'T/huge.gif'), 900, 1722)
      xml = write_xml(figures, '<p><graphic url="T/huge.gif"/></p>')

      with_odt(xml, figures_dir: figures) do |odt, _warnings|
        width, height = odt['content.xml'].match(/svg:width="([\d.]+)cm" svg:height="([\d.]+)cm"/).captures.map(&:to_f)

        # 輸出只保留 3 位小數, 比較時用同樣的精度
        assert_operator width, :<=, XmlToOdtConverter::MAX_IMAGE_WIDTH_CM.round(3)
        assert_operator height, :<=, XmlToOdtConverter::MAX_IMAGE_HEIGHT_CM.round(3)
        assert_in_delta 900.0 / 1722, width / height, 0.001 # 維持長寬比
      end
    end
  end

  test "找不到圖檔時退回文字佔位符" do
    with_odt(SAMPLE_XML, figures_dir: FIGURES) do |odt, warnings|
      assert_includes odt['content.xml'], '[image: T/missing.gif]'
      assert_includes warnings, 'Missing image file: T/missing.gif'
    end
  end

  test "未指定 figures_dir 時所有圖都是文字佔位符" do
    with_odt(SAMPLE_XML) do |odt, warnings|
      assert_empty odt.keys.grep(%r{\APictures/})
      assert_not_includes odt['META-INF/manifest.xml'], 'image/gif'
      assert_includes odt['content.xml'], '[image: T/sample.gif]'
      assert_includes warnings, 'figures_dir is not set; graphics are rendered as text placeholders.'
    end
  end

  test "相同格式共用一個 automatic style" do
    Dir.mktmpdir do |dir|
      body = '<p><seg style="font-weight:bold">甲</seg>乙<seg style="font-weight:bold">丙</seg></p>'
      with_odt(write_xml(dir, body)) do |odt, _warnings|
        content = odt['content.xml']
        names = content.scan(/<text:span text:style-name="(T\d+)">/).flatten

        assert_equal %w[T1 T1], names
        assert_equal 1, content.scan('style:family="text"').size
        # 與 default 相同的「乙」不需要 span
        assert_includes content, '</text:span>乙<text:span'
      end
    end
  end

  test "跨欄跨列的儲存格補上 covered cell" do
    Dir.mktmpdir do |dir|
      body = <<~XML
        <table cols="3">
          <row><cell cols="2" rows="2">甲</cell><cell>乙</cell></row>
          <row><cell>丙</cell></row>
        </table>
      XML
      with_odt(write_xml(dir, body)) do |odt, _warnings|
        table = Nokogiri::XML(odt['content.xml']).at_xpath('//table:table')
        rows = table.xpath('./table:table-row')

        # 每列都要湊滿 3 欄
        assert_equal [3, 3], rows.map { |row| row.element_children.size }
        assert_equal 3, table.xpath('.//table:covered-table-cell').size

        merged = rows.first.element_children.first
        assert_equal '2', merged['table:number-columns-spanned']
        assert_equal '2', merged['table:number-rows-spanned']
      end
    end
  end

  test "欄寬平均分配到版面寬度" do
    Dir.mktmpdir do |dir|
      body = '<table cols="4"><row><cell>甲</cell><cell>乙</cell><cell>丙</cell><cell>丁</cell></row></table>'
      with_odt(write_xml(dir, body)) do |odt, _warnings|
        content = odt['content.xml']
        column = Nokogiri::XML(content).at_xpath('//table:table-column')
        assert_equal '4', column['table:number-columns-repeated']

        width = content.match(/style:column-width="([\d.]+)cm"/)[1].to_f
        assert_in_delta XmlToOdtConverter::CONTENT_WIDTH_CM / 4, width, 0.01
      end
    end
  end

  test "註腳就地展開, 不需要獨立的 part" do
    Dir.mktmpdir do |dir|
      body = '<p>本文<footnote>註腳說明</footnote></p>'
      with_odt(write_xml(dir, body)) do |odt, _warnings|
        note = Nokogiri::XML(odt['content.xml']).at_xpath('//text:note')

        assert_equal 'footnote', note['text:note-class']
        assert_equal '1', note.at_xpath('./text:note-citation').text
        assert_includes note.at_xpath('./text:note-body').text, '註腳說明'
      end
    end
  end

  test "註腳裡的 table 拆成獨立的 table:table" do
    Dir.mktmpdir do |dir|
      body = '<p>本文<footnote>註腳說明<table cols="2"><row><cell>甲</cell><cell>乙</cell></row></table>表格後的字</footnote></p>'
      with_odt(write_xml(dir, body)) do |odt, _warnings|
        note_body = Nokogiri::XML(odt['content.xml']).at_xpath('//text:note/text:note-body')

        # table 不能包在 text:p 裡
        assert_equal 1, note_body.xpath('./table:table').size
        assert_empty note_body.xpath('.//text:p//table:table')
        assert_equal %w[p table p], note_body.element_children.map(&:name)
      end
    end
  end

  test "標題 style 轉成 text:h 並帶 outline level" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'input.xml')
      File.write(path, <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <document>
          <settings>
            <styles>
              <style name="default">font-size:12</style>
              <style name="標題 2">font-size:16;font-weight:bold</style>
            </styles>
          </settings>
          <body><p rend="標題 2">卷一</p></body>
        </document>
      XML

      with_odt(path) do |odt, _warnings|
        heading = Nokogiri::XML(odt['content.xml']).at_xpath('//text:h')
        assert_equal '2', heading['text:outline-level']
        assert_equal '卷一', heading.text

        # style:name 不能有空白, 原名放 display-name
        assert_includes odt['styles.xml'], 'style:display-name="標題 2"'
        assert_includes odt['styles.xml'], 'style:default-outline-level="2"'
      end
    end
  end

  test "footer 的頁碼變成 ODF 的頁碼欄位" do
    with_odt(SAMPLE_XML) do |odt, _warnings|
      footer = Nokogiri::XML(odt['styles.xml']).at_xpath('//style:master-page/style:footer')

      assert_equal 1, footer.xpath('.//text:page-number').size
      assert_equal 1, footer.xpath('.//text:page-count').size
      assert_includes footer.text, '頁'
    end
  end

  test "連續空白用 text:s 保留" do
    Dir.mktmpdir do |dir|
      with_odt(write_xml(dir, '<p>甲   乙</p>')) do |odt, _warnings|
        assert_includes odt['content.xml'], '甲 <text:s text:c="2"/>乙'
      end
    end
  end

  test "title 與 byline 寫進 meta.xml" do
    with_odt(SAMPLE_XML) do |odt, _warnings|
      assert_includes odt['meta.xml'], '<dc:title>圖片測試</dc:title>'
      assert_includes odt['meta.xml'], '<meta:initial-creator>測試</meta:initial-creator>'
    end
  end

  test "package 各 part 都是合法 XML" do
    with_odt(SAMPLE_XML, figures_dir: FIGURES) do |odt, _warnings|
      odt.each do |name, content|
        next unless name.end_with?('.xml')

        assert_empty Nokogiri::XML(content).errors, "#{name} 不是合法 XML"
      end
    end
  end

  private

  # 轉出 odt 並把 zip 內容讀成 { part 名稱 => 內容 }
  def with_odt(xml_path, figures_dir: nil)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'out.odt')
      warnings = XmlToOdtConverter.new(xml_path, figures_dir: figures_dir).convert(path)
      parts = {}
      Zip::File.open(path) do |zip|
        zip.each do |entry|
          content = entry.get_input_stream.read
          # 圖片保持 binary, 其餘都是 UTF-8 文字
          parts[entry.name] = entry.name.start_with?('Pictures/') ? content : content.force_encoding('UTF-8')
        end
      end
      yield parts, warnings
    end
  end

  # 只要 header 正確就能讀出尺寸, 測縮放不需要完整的圖片資料
  def write_gif_header(path, width, height)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, "GIF89a".b + [width, height].pack('v2') + "\x00\x00\x00".b)
  end

  def write_xml(dir, body)
    path = File.join(dir, 'input.xml')
    File.write(path, <<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <document>
        <settings>
          <footer>第 {Page} 頁／共 {NumPages} 頁</footer>
          <styles><style name="default">font-size:12</style></styles>
        </settings>
        <body>#{body}</body>
      </document>
    XML
    path
  end
end
