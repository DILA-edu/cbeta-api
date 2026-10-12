require 'test_helper'
require 'tmpdir'
require 'zip'

# DocxChecker 要能讓正確的轉檔通過, 也要能抓到被破壞的 docx
class DocxCheckerTest < ActiveSupport::TestCase
  FIXTURES = Rails.root.join('test/fixtures/files')
  SAMPLE_XML = FIXTURES.join('xml4docx/sample.xml').to_s
  FIGURES = FIXTURES.join('figures').to_s

  # list、table、註腳裡的 table 是文字比對最容易誤判的地方
  COMPLEX_BODY = <<~XML
    <p rend="標題">經名<footnote>校勘<table><row><cell>注中表</cell></row></table>表後</footnote></p>
    <list type="decimal">
      <item><p>第一項</p><list><item><p>子項</p></item></list></item>
      <item><seg>第二項</seg></item>
    </list>
    <list type="none"><item><p>無符號</p></item></list>
    <table><row><cell cols="2">跨欄</cell></row><row><cell>甲</cell><cell>乙<lb/>丙</cell></row></table>
    <p>　全形空白<!-- lb: T01n0001_p0001a01 -->與 comment</p>
  XML

  test '正確轉出的 docx 沒有錯誤' do
    with_converted(SAMPLE_XML, figures_dir: FIGURES) do |xml, docx|
      assert_empty DocxChecker.new(xml, docx).check
    end
  end

  test 'list、table、註腳裡的 table 不會誤判' do
    with_xml(COMPLEX_BODY) do |xml|
      with_converted(xml) do |_xml, docx|
        assert_empty DocxChecker.new(xml, docx).check
      end
    end
  end

  test '找不到圖檔時的文字佔位符算進 graphic 數量' do
    with_converted(SAMPLE_XML) do |xml, docx|
      assert_empty DocxChecker.new(xml, docx).check
    end
  end

  test '本文掉字時指出差異位置' do
    with_converted(SAMPLE_XML, figures_dir: FIGURES) do |xml, docx|
      tamper(docx, 'word/document.xml') { it.sub('同一張圖', '同張圖') }
      errors = DocxChecker.new(xml, docx).check

      assert_equal 1, errors.size
      assert_match(/本文 文字不符/, errors.first)
      assert_match(/xml4docx: ….*同一張圖/, errors.first)
    end
  end

  test '註腳文字不符時指出是第幾個註腳' do
    with_converted(SAMPLE_XML, figures_dir: FIGURES) do |xml, docx|
      tamper(docx, 'word/footnotes.xml') { it.sub('註腳內容', '註腳') }

      assert_equal 1, DocxChecker.new(xml, docx).check.grep(/footnote 1 文字不符/).size
    end
  end

  test '註腳引用與定義對不上' do
    with_converted(SAMPLE_XML, figures_dir: FIGURES) do |xml, docx|
      tamper(docx, 'word/document.xml') { it.sub('<w:footnoteReference w:id="1"/>', '<w:footnoteReference w:id="9"/>') }
      errors = DocxChecker.new(xml, docx).check

      assert_includes errors, 'document.xml 引用不存在的 footnote 9'
      assert_includes errors, 'footnote 1 沒有被引用'
    end
  end

  test 'relationship 指向不存在的 part' do
    with_converted(SAMPLE_XML, figures_dir: FIGURES) do |xml, docx|
      tamper(docx, 'word/_rels/document.xml.rels') { it.sub('media/image1.gif', 'media/nothing.gif') }

      assert_includes DocxChecker.new(xml, docx).check,
                      'word/_rels/document.xml.rels 的 rIdImg1 指向不存在的 word/media/nothing.gif'
    end
  end

  test 'Content_Types 沒有涵蓋圖檔副檔名' do
    with_converted(SAMPLE_XML, figures_dir: FIGURES) do |xml, docx|
      tamper(docx, '[Content_Types].xml') { it.sub(%r{<Default Extension="gif"[^>]*/>}, '') }

      assert_includes DocxChecker.new(xml, docx).check, '[Content_Types].xml 沒有涵蓋 word/media/image1.gif'
    end
  end

  test 'wp:docPr id 重複' do
    with_converted(SAMPLE_XML, figures_dir: FIGURES) do |xml, docx|
      tamper(docx, 'word/document.xml') { it.sub('<wp:docPr id="2"', '<wp:docPr id="1"') }

      assert_includes DocxChecker.new(xml, docx).check, 'wp:docPr id 重複: 1'
    end
  end

  test 'part 不是合法 XML' do
    with_converted(SAMPLE_XML, figures_dir: FIGURES) do |xml, docx|
      tamper(docx, 'word/styles.xml') { it.sub('</w:styles>', '') }

      assert_match(/\Aword\/styles.xml 不是合法 XML/, DocxChecker.new(xml, docx).check.first)
    end
  end

  test 'docx 不存在' do
    assert_equal [ 'docx 不存在: /nonexistent.docx' ], DocxChecker.new(SAMPLE_XML, '/nonexistent.docx').check
  end

  private

  def with_converted(xml_path, figures_dir: nil)
    Dir.mktmpdir do |dir|
      docx = File.join(dir, 'out.docx')
      XmlToDocxConverter.new(xml_path, figures_dir: figures_dir).convert(docx)
      yield xml_path, docx
    end
  end

  def with_xml(body)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'input.xml')
      File.write(path, <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <document>
          <settings><styles>
            <style name="default">font-size:12</style>
            <style name="標題">font-size:16</style>
          </styles></settings>
          <body>#{body}</body>
        </document>
      XML
      yield path
    end
  end

  # 改寫 docx 裡的某個 part, 其餘 part 原樣保留
  def tamper(docx, part_name)
    parts = Zip::File.open(docx) do |zip|
      zip.entries.to_h { [ it.name, it.get_input_stream.read ] }
    end
    parts[part_name] = yield(parts[part_name].force_encoding('UTF-8'))
    OfficeZipWriter.write(docx, parts)
  end
end
