# frozen_string_literal: true

require 'nokogiri'
require 'zip'

# 比對 xml4docx 與轉出的 docx, 檢查 package 結構與內容是否一致。
#
#   errors = DocxChecker.new(xml_path, docx_path).check
#
# 回傳錯誤訊息的陣列, 空陣列代表沒有問題。
# 文字比對會去掉 ASCII 空白, 只檢查字有沒有掉或多, 不檢查排版。
class DocxChecker
  W_NS = XmlToDocxConverter::W_NS
  NS = {
    'w' => W_NS,
    'wp' => XmlToDocxConverter::WP_NS,
    'r' => XmlToDocxConverter::R_NS,
    'rel' => XmlToDocxConverter::PKG_REL_NS,
    'ct' => 'http://schemas.openxmlformats.org/package/2006/content-types'
  }.freeze

  # 找不到圖檔時 converter 輸出的文字佔位符, 見 XmlToDocxConverter#graphic_xml
  IMAGE_PLACEHOLDER = /\[image: [^\]]*\]/

  # 文字不一致時, 前後各顯示幾個字
  CONTEXT_CHARS = 20

  def initialize(xml_path, docx_path)
    @xml_path = xml_path.to_s
    @docx_path = docx_path.to_s
    @errors = []
  end

  def check
    return [ "docx 不存在: #{@docx_path}" ] unless File.file?(@docx_path)

    @parts = read_parts
    @xml_parts = parse_xml_parts
    return @errors unless @errors.empty?

    @source = Nokogiri::XML(File.read(@xml_path, encoding: 'UTF-8'))
    @document = @xml_parts.fetch('word/document.xml')
    @footnotes = @xml_parts['word/footnotes.xml']

    check_content_types
    check_relationships
    check_footnote_ids
    check_drawing_ids
    check_counts
    check_body_text
    check_footnote_texts
    @errors
  rescue Zip::Error => e
    [ "docx 不是合法的 zip: #{e.message}" ]
  end

  private

  # --- 讀檔 ---

  def read_parts
    Zip::File.open(@docx_path) do |zip|
      zip.each_with_object({}) do |entry, parts|
        next if entry.directory?

        parts[entry.name] = entry.get_input_stream.read
      end
    end
  end

  def parse_xml_parts
    required = %w[[Content_Types].xml word/document.xml]
    required.each { error("缺少 part: #{it}") unless @parts.key?(it) }

    @parts.each_with_object({}) do |(name, data), parsed|
      next unless name.end_with?('.xml', '.rels')

      doc = Nokogiri::XML(data.dup.force_encoding('UTF-8'))
      if doc.errors.empty?
        parsed[name] = doc
      else
        error("#{name} 不是合法 XML: #{doc.errors.first}")
      end
    end
  end

  # --- package 結構 ---

  # 每個 part 都要能從 [Content_Types].xml 查到 content type
  def check_content_types
    types = @xml_parts.fetch('[Content_Types].xml')
    defaults = types.xpath('//ct:Default/@Extension', NS).map { it.value.downcase }
    overrides = types.xpath('//ct:Override/@PartName', NS).map { it.value.delete_prefix('/') }

    @parts.each_key do |name|
      next if name == '[Content_Types].xml'
      next if overrides.include?(name) || defaults.include?(extension(name))

      error("[Content_Types].xml 沒有涵蓋 #{name}")
    end
  end

  # .rels 的 Target 要存在, part 裡用到的 r:embed / r:id 要有對應的 relationship
  def check_relationships
    @xml_parts.each do |name, doc|
      next unless name.end_with?('.rels')

      source_part = rels_source_part(name)
      ids = doc.xpath('//rel:Relationship', NS).map do |rel|
        check_relationship_target(name, source_part, rel)
        rel['Id']
      end
      check_relationship_references(source_part, ids)
    end
  end

  def check_relationship_target(rels_name, source_part, rel)
    return if rel['TargetMode'] == 'External'

    target = resolve_target(source_part, rel['Target'].to_s)
    error("#{rels_name} 的 #{rel['Id']} 指向不存在的 #{target}") unless @parts.key?(target)
  end

  def check_relationship_references(source_part, ids)
    doc = @xml_parts[source_part]
    return if doc.nil?

    doc.xpath('//@r:embed | //@r:id', NS).each do |attr|
      error("#{source_part} 用到未定義的 relationship #{attr.value}") unless ids.include?(attr.value)
    end
  end

  # word/_rels/document.xml.rels 對應 word/document.xml; 根目錄的 _rels/.rels 對應空字串
  def rels_source_part(rels_name)
    dir = File.dirname(rels_name, 2)
    base = File.basename(rels_name).delete_suffix('.rels')
    dir == '.' ? base : File.join(dir, base)
  end

  # Target 相對於 source part 所在目錄; source part 為空字串時是 package 根目錄的 _rels/.rels
  def resolve_target(source_part, target)
    return target.delete_prefix('/') if target.start_with?('/')

    base = File.dirname(source_part)
    path = base == '.' ? target : File.join(base, target)
    File.expand_path(path, '/').delete_prefix('/')
  end

  def check_footnote_ids
    references = @document.xpath('//w:footnoteReference/@w:id', NS).map(&:value)
    notes = footnote_nodes.map { it['w:id'] }

    duplicated(notes).each { error("footnotes.xml 的 w:id 重複: #{it}") }
    duplicated(references).each { error("document.xml 重複引用 footnote #{it}") }
    (references - notes).uniq.each { error("document.xml 引用不存在的 footnote #{it}") }
    (notes - references).uniq.each { error("footnote #{it} 沒有被引用") }
  end

  # Word 要求 wp:docPr 的 id 在整份文件唯一, 重複時開檔會要求修復
  def check_drawing_ids
    ids = word_parts.flat_map { |doc| doc.xpath('//wp:docPr/@id', NS).map(&:value) }
    duplicated(ids).each { error("wp:docPr id 重複: #{it}") }
  end

  # --- 內容 ---

  def check_counts
    compare_count('footnote', source_body.xpath('.//footnote').size, footnote_nodes.size)
    compare_count('table', source_body.xpath('.//table').size,
                  word_parts.sum { it.xpath('//w:tbl', NS).size })

    drawings = word_parts.sum { it.xpath('//w:drawing', NS).size }
    placeholders = word_parts.sum { docx_text(it.xpath('//w:t', NS)).scan(IMAGE_PLACEHOLDER).size }
    compare_count('graphic', source_body.xpath('.//graphic').size, drawings + placeholders)
  end

  def compare_count(name, expected, actual)
    error("#{name} 數量不符: xml4docx #{expected}, docx #{actual}") unless expected == actual
  end

  def check_body_text
    expected = +''
    collect_text(source_body, expected)
    actual = docx_text(@document.xpath('/w:document/w:body//w:t', NS))
    compare_text('本文', expected, actual)
  end

  # footnote 依出現順序從 1 編號, 見 XmlToDocxConverter#add_footnote
  def check_footnote_texts
    docx_notes = footnote_nodes.to_h { [ it['w:id'], it ] }

    source_body.xpath('.//footnote').each.with_index(1) do |note, id|
      docx_note = docx_notes[id.to_s]
      next if docx_note.nil? # 數量不符已在 check_counts 報過

      expected = +''
      collect_text(note, expected)
      compare_text("footnote #{id}", expected, docx_text(docx_note.xpath('.//w:t', NS)))
    end
  end

  # 依 converter 的規則收集 xml4docx 應該出現在 docx 的文字
  # footnote 的內容在 footnotes.xml, 不算在所屬的本文或外層 footnote 裡
  def collect_text(node, out)
    node.children.each do |child|
      if child.text?
        out << child.text
      elsif child.element?
        case child.name
        when 'footnote' then next
        when 'list' then collect_list_text(child, out)
        else collect_text(child, out)
        end
      end
    end
  end

  # list item 的第一段會加上項目符號, 與 Xml4docxSupport#list_marker 一致
  def collect_list_text(list, out)
    list.xpath('./item').each_with_index do |item, index|
      out << list_marker(list['type'].to_s, index)
      collect_text(item, out)
    end
  end

  def list_marker(type, index)
    case type
    when 'none' then ''
    when 'decimal', 'number', 'ordered' then "#{index + 1}."
    else '•'
    end
  end

  def compare_text(label, expected, actual)
    expected = squeeze(expected)
    actual = squeeze(actual.gsub(IMAGE_PLACEHOLDER, ''))
    return if expected == actual

    index = first_difference(expected, actual)
    error(<<~MSG.chomp)
      #{label} 文字不符 (xml4docx #{expected.size} 字, docx #{actual.size} 字), 第 #{index} 字起:
        xml4docx: #{context(expected, index)}
        docx:     #{context(actual, index)}
    MSG
  end

  def first_difference(a, b)
    a.each_char.with_index { |char, i| return i if char != b[i] }
    a.size
  end

  def context(text, index)
    start = [ index - CONTEXT_CHARS, 0 ].max
    "…#{text[start, CONTEXT_CHARS * 2]}…"
  end

  # --- 共用 ---

  def source_body
    @source_body ||= @source.at_xpath('/document/body') || raise("Missing /document/body in #{@xml_path}")
  end

  # 排除 separator (-1) 與 continuationSeparator (0)
  def footnote_nodes
    return [] if @footnotes.nil?

    @footnote_nodes ||= @footnotes.xpath('//w:footnote[not(@w:type)]', NS)
  end

  def word_parts
    [ @document, @footnotes ].compact
  end

  def docx_text(nodes)
    nodes.map(&:text).join
  end

  # 只去掉 ASCII 空白; 全形空白等是經文內容, 要保留比對
  def squeeze(text)
    text.gsub(/\s+/, '')
  end

  # File.extname 對 .rels 這種以點開頭的檔名會回傳空字串, 所以自己取
  def extension(name)
    name[%r{\.([^./]+)\z}, 1].to_s.downcase
  end

  def duplicated(values)
    values.tally.select { |_value, count| count > 1 }.keys
  end

  def error(message)
    @errors << message
  end
end
