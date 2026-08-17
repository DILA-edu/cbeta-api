require 'test_helper'
require 'tmpdir'
require 'zip'

# 鎖住 xml4docx 轉 docx 的 package 結構, 重點在 <graphic> 的圖片嵌入。
class XmlToDocxConverterTest < ActiveSupport::TestCase
  FIXTURES = Rails.root.join('test/fixtures/files')
  SAMPLE_XML = FIXTURES.join('xml4docx/sample.xml').to_s
  FIGURES = FIXTURES.join('figures').to_s

  test "圖片嵌入 word/media 並建立 relationship" do
    with_docx(SAMPLE_XML, figures_dir: FIGURES) do |docx, _warnings|
      # 同一張圖用了三次 (body 兩次 + footnote 一次), 只存一份 media
      assert_equal ['word/media/image1.gif'], docx.keys.grep(%r{\Aword/media/})
      assert_equal File.binread(File.join(FIGURES, 'T/sample.gif')), docx['word/media/image1.gif']

      assert_includes docx['[Content_Types].xml'], '<Default Extension="gif" ContentType="image/gif"/>'
      assert_includes docx['word/_rels/document.xml.rels'], 'Id="rIdImg1"'
      assert_includes docx['word/_rels/document.xml.rels'], 'Target="media/image1.gif"'
      assert_equal 2, docx['word/document.xml'].scan('r:embed="rIdImg1"').size
    end
  end

  test "註腳裡的圖用 footnotes.xml 自己的 relationship" do
    with_docx(SAMPLE_XML, figures_dir: FIGURES) do |docx, _warnings|
      assert_includes docx['word/_rels/footnotes.xml.rels'], 'Id="rIdFnImg1"'
      assert_includes docx['word/_rels/footnotes.xml.rels'], 'Target="media/image1.gif"'
      assert_includes docx['word/footnotes.xml'], 'r:embed="rIdFnImg1"'
      # footnotes.xml 用到 r:embed, 必須宣告 r namespace
      assert_includes docx['word/footnotes.xml'], "xmlns:r=\"#{XmlToDocxConverter::R_NS}\""
    end
  end

  test "圖片以 96 DPI 換算 EMU" do
    with_docx(SAMPLE_XML, figures_dir: FIGURES) do |docx, _warnings|
      # sample.gif 是 44x35 px
      cx = 44 * XmlToDocxConverter::EMU_PER_PIXEL
      cy = 35 * XmlToDocxConverter::EMU_PER_PIXEL
      assert_includes docx['word/document.xml'], "<wp:extent cx=\"#{cx}\" cy=\"#{cy}\"/>"
    end
  end

  test "超出版面的圖等比縮小" do
    Dir.mktmpdir do |figures|
      write_gif_header(File.join(figures, 'T/huge.gif'), 900, 1722)
      xml = write_xml(figures, '<p><graphic url="T/huge.gif"/></p>')

      with_docx(xml, figures_dir: figures) do |docx, _warnings|
        cx, cy = docx['word/document.xml'].match(/<wp:extent cx="(\d+)" cy="(\d+)"\/>/).captures.map(&:to_i)

        assert_operator cx, :<=, XmlToDocxConverter::MAX_IMAGE_WIDTH_EMU
        assert_operator cy, :<=, XmlToDocxConverter::MAX_IMAGE_HEIGHT_EMU
        assert_in_delta 900.0 / 1722, cx.to_f / cy, 0.001 # 維持長寬比
      end
    end
  end

  test "找不到圖檔時退回文字佔位符" do
    with_docx(SAMPLE_XML, figures_dir: FIGURES) do |docx, warnings|
      assert_includes docx['word/document.xml'], '[image: T/missing.gif]'
      assert_includes warnings, 'Missing image file: T/missing.gif'
    end
  end

  test "未指定 figures_dir 時所有圖都是文字佔位符" do
    with_docx(SAMPLE_XML) do |docx, warnings|
      assert_empty docx.keys.grep(%r{\Aword/media/})
      assert_not_includes docx['[Content_Types].xml'], 'image/gif'
      assert_not_includes docx.keys, 'word/_rels/footnotes.xml.rels'
      assert_includes docx['word/document.xml'], '[image: T/sample.gif]'
      assert_includes warnings, 'figures_dir is not set; graphics are rendered as text placeholders.'
    end
  end

  test "註腳裡的 table 拆成獨立的 w:tbl" do
    Dir.mktmpdir do |dir|
      body = '<p>本文<footnote>註腳說明<table cols="2"><row><cell>甲</cell><cell>乙</cell></row></table>表格後的字</footnote></p>'
      with_docx(write_xml(dir, body)) do |docx, _warnings|
        footnotes = Nokogiri::XML(docx['word/footnotes.xml'])
        note = footnotes.xpath('//w:footnote[@w:id="1"]').first

        # w:tbl 不能包在 w:p 裡
        assert_equal 1, note.xpath('.//w:tbl').size
        assert_empty note.xpath('.//w:p//w:tbl')

        # 註腳編號在第一個段落, 表格前後都有段落
        kinds = note.element_children.map(&:name)
        assert_equal %w[p tbl p], kinds
        assert_equal 1, note.element_children.first.xpath('.//w:footnoteRef').size
        assert_includes note.element_children.first.text, '註腳說明'
        assert_includes note.element_children.last.text, '表格後的字'
      end
    end
  end

  test "註腳開頭就是 table 時仍保有註腳編號" do
    Dir.mktmpdir do |dir|
      body = '<p>本文<footnote><table cols="1"><row><cell>甲</cell></row></table></footnote></p>'
      with_docx(write_xml(dir, body)) do |docx, _warnings|
        note = Nokogiri::XML(docx['word/footnotes.xml']).xpath('//w:footnote[@w:id="1"]').first

        assert_equal %w[p tbl p], note.element_children.map(&:name)
        assert_equal 1, note.xpath('.//w:footnoteRef').size
      end
    end
  end

  test "package 各 part 都是合法 XML" do
    with_docx(SAMPLE_XML, figures_dir: FIGURES) do |docx, _warnings|
      docx.each do |name, content|
        next unless name.end_with?('.xml', '.rels')

        errors = Nokogiri::XML(content).errors
        assert_empty errors, "#{name} 不是合法 XML"
      end
    end
  end

  private

  # 轉出 docx 並把 zip 內容讀成 { part 名稱 => 內容 }
  def with_docx(xml_path, figures_dir: nil)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'out.docx')
      warnings = XmlToDocxConverter.new(xml_path, figures_dir: figures_dir).convert(path)
      parts = {}
      Zip::File.open(path) { |zip| zip.each { parts[it.name] = it.get_input_stream.read } }
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
        <settings><styles><style name="default">font-size:12</style></styles></settings>
        <body>#{body}</body>
      </document>
    XML
    path
  end
end
