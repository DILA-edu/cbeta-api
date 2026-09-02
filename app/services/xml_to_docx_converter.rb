# frozen_string_literal: true

require 'nokogiri'
require 'time'

# 把 xml4docx 中間格式轉為 docx (OOXML)
#
#   XmlToDocxConverter.new(xml_path, figures_dir: dir).convert(docx_path)
#
# figures_dir 是 CBR2X-figures 的路徑; 未指定時 <graphic> 會退回文字佔位符。
class XmlToDocxConverter
  include Xml4docxSupport

  W_NS = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
  R_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
  PKG_REL_NS = 'http://schemas.openxmlformats.org/package/2006/relationships'
  OFFICE_REL_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
  WP_NS = 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'
  A_NS = 'http://schemas.openxmlformats.org/drawingml/2006/main'
  PIC_NS = 'http://schemas.openxmlformats.org/drawingml/2006/picture'

  # 中文字型只套在 eastAsia, 西文另外指定, 否則英文與羅馬轉寫會被中文字型撐開字距
  WESTERN_FONT = 'Times New Roman'

  # 圖片以 96 DPI 換算 EMU
  EMU_PER_PIXEL = 9525
  EMU_PER_TWIP = 635
  PAGE_WIDTH_TWIPS = 11_906
  PAGE_HEIGHT_TWIPS = 16_838
  PAGE_MARGIN_TWIPS = 1440
  # 圖片最大尺寸: 版面可用寬高
  # 高度留 10% 餘裕, 否則整頁高的圖會把同段落的文字擠到上一頁, 留下大片空白
  MAX_IMAGE_WIDTH_EMU = (PAGE_WIDTH_TWIPS - (PAGE_MARGIN_TWIPS * 2)) * EMU_PER_TWIP
  MAX_IMAGE_HEIGHT_EMU = ((PAGE_HEIGHT_TWIPS - (PAGE_MARGIN_TWIPS * 2)) * EMU_PER_TWIP * 0.9).round

  # relationship id 前綴, 每個 part 各自一組 relationship
  IMAGE_REL_PREFIXES = { document: 'rIdImg', footnotes: 'rIdFnImg' }.freeze

  def initialize(input_path, figures_dir: nil)
    @input_path = input_path
    @figures_dir = figures_dir
    @xml = Nokogiri::XML(File.read(input_path, encoding: 'UTF-8')) { |config| config.strict }
    @styles = read_styles
    @default_style = @styles.fetch('default', {})
    @footnotes = []
    @warnings = []
    @images = {}         # url => 圖片資訊 (讀不到時為 nil)
    @media = {}          # url => { name:, data: }
    @image_rels = {}     # part => { url => relationship id }
    @current_part = :document
    @drawing_id = 0
  end

  def convert(output_path)
    OfficeZipWriter.write(output_path, package_parts)
    @warnings.uniq
  end

  private

  def package_parts
    # document 與 footnotes 先產生, 之後才知道用到哪些圖片
    document = document_xml
    footnotes = footnotes_xml

    parts = {
      '[Content_Types].xml' => content_types_xml,
      '_rels/.rels' => root_relationships_xml,
      'docProps/core.xml' => core_properties_xml,
      'docProps/app.xml' => app_properties_xml,
      'word/document.xml' => document,
      'word/_rels/document.xml.rels' => document_relationships_xml,
      'word/styles.xml' => styles_xml,
      'word/settings.xml' => settings_xml,
      'word/fontTable.xml' => font_table_xml,
      'word/footer1.xml' => footer_xml,
      'word/footnotes.xml' => footnotes
    }
    parts['word/_rels/footnotes.xml.rels'] = footnotes_relationships_xml if image_rels(:footnotes).any?
    @media.each_value { |media| parts["word/#{media[:name]}"] = media[:data] }
    parts
  end

  def document_xml
    body = @xml.at_xpath('/document/body')
    raise "Missing /document/body in #{@input_path}" unless body

    blocks = body.element_children.map { |node| block_xml(node) }.join

    xml_decl(
      <<~XML
        <w:document xmlns:w="#{W_NS}" xmlns:r="#{R_NS}">
          <w:body>
            #{blocks}
            #{section_properties_xml}
          </w:body>
        </w:document>
      XML
    )
  end

  def block_xml(node, list_context = nil)
    case node.name
    when 'p'
      paragraph_xml(node, list_context: list_context)
    when 'list'
      list_xml(node)
    when 'table'
      table_xml(node)
    else
      warn_once("Skipping unsupported block element <#{node.name}>.")
      ''
    end
  end

  def paragraph_xml(node, list_context: nil, prefix: nil, inherited_style: nil)
    style = merge_styles(inherited_style, style_for(node))
    pstyle_name = paragraph_style_name(node)
    style = style.merge('_pstyle' => pstyle_name) if pstyle_name
    runs = +''
    runs << run_xml(prefix, style) if prefix
    runs << inline_content_xml(node.children, style)

    paragraph_from_runs_xml(runs, style, list_context)
  end

  def paragraph_from_runs_xml(runs, style, list_context)
    runs = '<w:r/>' if runs.empty?
    <<~XML
      <w:p>
        #{paragraph_properties_xml(style, list_context)}
        #{runs}
      </w:p>
    XML
  end

  def list_xml(node)
    level = positive_integer(node['level'], 1)
    type = node['type'].to_s.empty? ? 'bullet' : node['type'].to_s

    node.xpath('./item').each_with_index.map do |item, index|
      item_xml(item, level, type, index)
    end.join
  end

  def item_xml(item, level, type, index)
    list_context = { level: level, type: type }
    marker = list_marker(type, index)

    item.element_children.map.with_index do |child, child_index|
      case child.name
      when 'p'
        paragraph_xml(child, list_context: list_context, prefix: child_index.zero? ? marker : nil)
      when 'list'
        list_xml(child)
      when 'seg'
        synthetic = Nokogiri::XML::Node.new('p', @xml)
        synthetic.add_child(child.dup)
        paragraph_xml(synthetic, list_context: list_context, prefix: child_index.zero? ? marker : nil)
      else
        warn_once("Skipping unsupported list item element <#{child.name}>.")
        ''
      end
    end.join
  end

  def table_xml(node, inherited_style: nil)
    style = merge_styles(inherited_style, style_for(node))
    rows = node.xpath('./row').to_a
    column_count = table_column_count(node, rows)

    <<~XML
      <w:tbl>
        <w:tblPr>
          #{width_xml(style['width'], 'w:tblW')}
          <w:tblBorders>
            <w:top w:val="single" w:sz="4" w:space="0" w:color="808080"/>
            <w:left w:val="single" w:sz="4" w:space="0" w:color="808080"/>
            <w:bottom w:val="single" w:sz="4" w:space="0" w:color="808080"/>
            <w:right w:val="single" w:sz="4" w:space="0" w:color="808080"/>
            <w:insideH w:val="single" w:sz="4" w:space="0" w:color="808080"/>
            <w:insideV w:val="single" w:sz="4" w:space="0" w:color="808080"/>
          </w:tblBorders>
          <w:tblLayout w:type="fixed"/>
          <w:tblCellMar>
            <w:top w:w="80" w:type="dxa"/>
            <w:left w:w="80" w:type="dxa"/>
            <w:bottom w:w="80" w:type="dxa"/>
            <w:right w:w="80" w:type="dxa"/>
          </w:tblCellMar>
        </w:tblPr>
        #{table_grid_xml(column_count)}
        #{table_rows_xml(rows, style)}
      </w:tbl>
    XML
  end

  def table_grid_xml(column_count)
    width = (9000 / column_count).floor
    columns = Array.new(column_count) { "<w:gridCol w:w=\"#{width}\"/>" }.join
    "<w:tblGrid>#{columns}</w:tblGrid>"
  end

  def table_rows_xml(rows, table_style)
    active_spans = {}

    rows.map { |row| row_xml(row, table_style, active_spans) }.join
  end

  def row_xml(node, table_style, active_spans)
    source_cells = node.xpath('./cell').to_a
    cell_index = 0
    column = 0
    cells = +''

    while cell_index < source_cells.length || active_span_at_or_after?(active_spans, column)
      if (span = active_spans[column])
        cells << vertical_merge_continuation_cell_xml(span[:cols])
        span[:remaining_rows] -= 1
        active_spans.delete(column) if span[:remaining_rows].zero?
        column += span[:cols]
        next
      end

      if cell_index < source_cells.length
        cell = source_cells[cell_index]
        cols = positive_integer(cell['cols'], 1)
        rows = positive_integer(cell['rows'], 1)

        cells << cell_xml(cell, table_style)
        active_spans[column] = { cols: cols, remaining_rows: rows - 1 } if rows > 1
        column += cols
        cell_index += 1
        next
      end

      cells << empty_cell_xml
      column += 1
    end

    "<w:tr>#{cells}</w:tr>"
  end

  def cell_xml(node, table_style)
    style = merge_styles(table_style, style_for(node))
    content = cell_content_xml(node, style)

    <<~XML
      <w:tc>
        #{cell_properties_xml(node)}
        #{content}
      </w:tc>
    XML
  end

  def cell_content_xml(node, style)
    return paragraph_from_runs_xml(inline_content_xml(node.children, style), style, nil) unless node.at_xpath('./p')

    paragraphs = []
    inline_nodes = []

    node.children.each do |child|
      if child.element? && child.name == 'p'
        paragraphs << cell_inline_paragraph_xml(inline_nodes, style)
        inline_nodes = []
        paragraphs << paragraph_xml(child, inherited_style: style)
      else
        inline_nodes << child
      end
    end

    paragraphs << cell_inline_paragraph_xml(inline_nodes, style)
    paragraphs.reject(&:empty?).join
  end

  def cell_inline_paragraph_xml(nodes, style)
    runs = inline_content_xml(nodes, style)
    return '' if runs.empty?

    paragraph_from_runs_xml(runs, style, nil)
  end

  def vertical_merge_continuation_cell_xml(cols)
    <<~XML
      <w:tc>
        #{cell_properties_for(cols, vertical_merge: 'continue')}
        <w:p/>
      </w:tc>
    XML
  end

  def empty_cell_xml
    <<~XML
      <w:tc>
        #{cell_properties_for(1)}
        <w:p/>
      </w:tc>
    XML
  end

  def cell_properties_xml(node)
    cols = positive_integer(node['cols'], 1)
    rows = positive_integer(node['rows'], 1)
    style = style_for(node)

    cell_properties_for(cols, width: style['width'], vertical_merge: rows > 1 ? 'restart' : nil)
  end

  def cell_properties_for(cols, width: nil, vertical_merge: nil)
    props = [width_xml(width, 'w:tcW')]
    props << "<w:gridSpan w:val=\"#{cols}\"/>" if cols > 1
    props << "<w:vMerge w:val=\"#{vertical_merge}\"/>" if vertical_merge

    "<w:tcPr>#{props.join}</w:tcPr>"
  end

  def inline_content_xml(nodes, inherited_style)
    nodes.map do |node|
      case node
      when Nokogiri::XML::Text
        text = normalize_text(node.text)
        text.empty? ? '' : run_xml(text, inherited_style)
      when Nokogiri::XML::Comment, Nokogiri::XML::ProcessingInstruction
        ''
      when Nokogiri::XML::Element
        inline_element_xml(node, inherited_style)
      else
        ''
      end
    end.join
  end

  def inline_element_xml(node, inherited_style)
    case node.name
    when 'lb'
      break_xml(inherited_style)
    when 'seg'
      inline_content_xml(node.children, merge_styles(inherited_style, style_for(node)))
    when 'font'
      style = merge_styles(inherited_style, style_for(node))
      style = merge_styles(style, 'font-family' => font_name_for(node['name'])) if node['name'].present?
      inline_content_xml(node.children, style)
    when 'p'
      inline_content_xml(node.children, merge_styles(inherited_style, style_for(node)))
    when 'footnote'
      footnote_reference_xml(add_footnote(node), footnote_reference_style(node, inherited_style))
    when 'graphic'
      graphic_xml(node, inherited_style)
    else
      warn_once("Skipping unsupported inline element <#{node.name}>.")
      ''
    end
  end

  def add_footnote(node)
    id = @footnotes.length + 1
    @footnotes << [id, node.dup]
    id
  end

  # --- 圖片 ---

  def graphic_xml(node, inherited_style)
    url = node['url'].to_s
    image = image_for(url)
    return run_xml("[image: #{url}]", inherited_style) if image.nil?

    drawing_xml(url, image)
  end

  def drawing_xml(url, image)
    rel_id = image_relationship_id(url, image)
    cx, cy = image_extent_emu(image)
    @drawing_id += 1
    name = escape_xml(File.basename(url))

    <<~XML.delete("\n")
      <w:r><w:drawing>
      <wp:inline xmlns:wp="#{WP_NS}" distT="0" distB="0" distL="0" distR="0">
      <wp:extent cx="#{cx}" cy="#{cy}"/>
      <wp:effectExtent l="0" t="0" r="0" b="0"/>
      <wp:docPr id="#{@drawing_id}" name="#{name}" descr="#{escape_xml(url)}"/>
      <wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="#{A_NS}" noChangeAspect="1"/></wp:cNvGraphicFramePr>
      <a:graphic xmlns:a="#{A_NS}"><a:graphicData uri="#{PIC_NS}">
      <pic:pic xmlns:pic="#{PIC_NS}">
      <pic:nvPicPr><pic:cNvPr id="#{@drawing_id}" name="#{name}"/><pic:cNvPicPr/></pic:nvPicPr>
      <pic:blipFill><a:blip r:embed="#{rel_id}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
      <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="#{cx}" cy="#{cy}"/></a:xfrm>
      <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
      </pic:pic></a:graphicData></a:graphic></wp:inline>
      </w:drawing></w:r>
    XML
  end

  # 等比縮到版面可用範圍內
  def image_extent_emu(image)
    cx = image[:width] * EMU_PER_PIXEL
    cy = image[:height] * EMU_PER_PIXEL
    scale = [1.0, MAX_IMAGE_WIDTH_EMU / cx.to_f, MAX_IMAGE_HEIGHT_EMU / cy.to_f].min

    [[(cx * scale).round, 1].max, [(cy * scale).round, 1].max]
  end

  def image_rels(part)
    @image_rels[part] ||= {}
  end

  # 同一張圖在 document 與 footnotes 共用 media 檔, 但各自需要一個 relationship
  def image_relationship_id(url, image)
    rels = image_rels(@current_part)
    rels[url] ||= begin
      register_media(url, image)
      "#{IMAGE_REL_PREFIXES.fetch(@current_part)}#{rels.size + 1}"
    end
  end

  def register_media(url, image)
    @media[url] ||= { name: "media/image#{@media.size + 1}.#{image[:extension]}", data: image[:data] }
  end

  def image_relationships_xml(part)
    image_rels(part).map do |url, rel_id|
      %(<Relationship Id="#{rel_id}" Type="#{OFFICE_REL_NS}/image" Target="#{@media.fetch(url)[:name]}"/>)
    end.join
  end

  def media_extensions
    @media.each_value.map { |media| File.extname(media[:name]).delete_prefix('.') }.uniq
  end

  # --- 其餘 part ---

  def run_xml(text, style)
    <<~XML.delete("\n")
      <w:r>
        #{run_properties_xml(style)}
        <w:t xml:space="preserve">#{escape_xml(text)}</w:t>
      </w:r>
    XML
  end

  def break_xml(style)
    "<w:r>#{run_properties_xml(style)}<w:br/></w:r>"
  end

  def footnote_reference_xml(id, style)
    <<~XML.delete("\n")
      <w:r>
        #{run_properties_xml(style, rstyle: 'FootnoteReference')}
        <w:footnoteReference w:id="#{id}"/>
      </w:r>
    XML
  end

  def footnotes_xml
    @current_part = :footnotes
    notes = @footnotes.map { |id, node| footnote_xml(id, node) }.join
    @current_part = :document

    xml_decl(
      <<~XML
        <w:footnotes xmlns:w="#{W_NS}" xmlns:r="#{R_NS}">
          <w:footnote w:type="separator" w:id="-1">
            <w:p><w:r><w:separator/></w:r></w:p>
          </w:footnote>
          <w:footnote w:type="continuationSeparator" w:id="0">
            <w:p><w:r><w:continuationSeparator/></w:r></w:p>
          </w:footnote>
          #{notes}
        </w:footnotes>
      XML
    )
  end

  def footnote_xml(id, node)
    style = merge_styles(@default_style, 'font-size' => '10')

    <<~XML
      <w:footnote w:id="#{id}">
        #{footnote_blocks_xml(node, style)}
      </w:footnote>
    XML
  end

  # 註腳通常只有一段文字, 但可能夾雜 table; w:tbl 不能包在 w:p 裡, 必須拆成多個 block
  def footnote_blocks_xml(node, style)
    blocks = +''
    reference_pending = true
    last_kind = nil

    footnote_groups(node.children).each do |kind, value|
      if kind == :table
        # 註腳編號一定要在第一個段落, table 之前先補一個
        blocks << footnote_paragraph_xml('', reference: true) if reference_pending
        blocks << table_xml(value, inherited_style: style)
      else
        runs = inline_content_xml(value, style)
        next if runs.empty?

        blocks << footnote_paragraph_xml(runs, reference: reference_pending)
      end
      reference_pending = false
      last_kind = kind
    end

    # 註腳至少要有一個段落, 且 w:tbl 之後必須再接一個段落
    blocks << footnote_paragraph_xml('', reference: reference_pending) if last_kind.nil? || last_kind == :table
    blocks
  end

  # 把註腳子節點切成 [:inline, nodes] 與 [:table, node] 兩種區段
  def footnote_groups(children)
    children.each_with_object([]) do |child, groups|
      if child.element? && child.name == 'table'
        groups << [:table, child]
      elsif groups.last&.first == :inline
        groups.last[1] << child
      else
        groups << [:inline, [child]]
      end
    end
  end

  def footnote_paragraph_xml(runs, reference: false)
    marker = if reference
                <<~XML.delete("\n")
                  <w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:footnoteRef/></w:r>
                  <w:r><w:t xml:space="preserve"> </w:t></w:r>
                XML
              else
                ''
              end

    <<~XML
      <w:p>
        <w:pPr><w:pStyle w:val="FootnoteText"/></w:pPr>
        #{marker}
        #{runs}
      </w:p>
    XML
  end

  def paragraph_properties_xml(style, list_context)
    props = []

    props << "<w:pStyle w:val=\"#{escape_xml(style['_pstyle'])}\"/>" if style['_pstyle']

    if (alignment = alignment_value(style['text-align'] || style['cell-align']))
      props << "<w:jc w:val=\"#{alignment}\"/>"
    end

    if (fill = color_value(style['background-color']))
      props << "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"#{fill}\"/>"
    end

    if list_context
      left = [list_context[:level], 1].max * 720
      props << "<w:ind w:left=\"#{left}\"/>"
    end

    props.empty? ? '' : "<w:pPr>#{props.join}</w:pPr>"
  end

  # extra 是額外的 rPr 子元素, 由呼叫端負責放在符合 CT_RPr 順序的位置
  def run_properties_xml(style, extra: nil, rstyle: nil)
    effective = merge_styles(@default_style, style)
    # 子元素順序依 CT_RPr 的 schema sequence
    props = []

    props << "<w:rStyle w:val=\"#{escape_xml(rstyle)}\"/>" if rstyle

    if (font = effective['font-family'])
      east_asia = escape_xml(font)
      western = escape_xml(font.match?(/\p{Han}/) ? WESTERN_FONT : font)
      props << "<w:rFonts w:ascii=\"#{western}\" w:hAnsi=\"#{western}\" w:eastAsia=\"#{east_asia}\" w:cs=\"#{western}\"/>"
    end

    props << '<w:b/><w:bCs/>' if bold?(effective['font-weight'])

    props << extra if extra

    if (color = color_value(effective['color']))
      props << "<w:color w:val=\"#{color}\"/>"
    end

    if (size = half_points(effective['font-size']))
      props << "<w:sz w:val=\"#{size}\"/><w:szCs w:val=\"#{size}\"/>"
    end

    if (fill = color_value(effective['background-color']))
      props << "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"#{fill}\"/>"
    end

    props.empty? ? '' : "<w:rPr>#{props.join}</w:rPr>"
  end

  def section_properties_xml
    <<~XML
      <w:sectPr>
        <w:footerReference w:type="default" r:id="rIdFooter"/>
        <w:pgSz w:w="#{PAGE_WIDTH_TWIPS}" w:h="#{PAGE_HEIGHT_TWIPS}"/>
        <w:pgMar w:top="#{PAGE_MARGIN_TWIPS}" w:right="#{PAGE_MARGIN_TWIPS}" w:bottom="#{PAGE_MARGIN_TWIPS}" w:left="#{PAGE_MARGIN_TWIPS}" w:header="720" w:footer="720" w:gutter="0"/>
        <w:cols w:space="720"/>
        <w:docGrid w:linePitch="360"/>
      </w:sectPr>
    XML
  end

  def footer_xml
    footer = text_at('/document/settings/footer')

    xml_decl(
      <<~XML
        <w:ftr xmlns:w="#{W_NS}">
          <w:p>
            <w:pPr><w:jc w:val="center"/></w:pPr>
            #{footer_runs_xml(footer)}
          </w:p>
        </w:ftr>
      XML
    )
  end

  def footer_runs_xml(footer)
    footer.to_s.split(/(\{Page\}|\{NumPages\})/).map do |part|
      case part
      when '{Page}'
        field_xml('PAGE', '1')
      when '{NumPages}'
        field_xml('NUMPAGES', '1')
      else
        part.empty? ? '' : run_xml(part, @default_style)
      end
    end.join
  end

  def field_xml(instruction, placeholder)
    <<~XML.delete("\n")
      <w:r><w:fldChar w:fldCharType="begin"/></w:r>
      <w:r><w:instrText xml:space="preserve"> #{instruction} </w:instrText></w:r>
      <w:r><w:fldChar w:fldCharType="separate"/></w:r>
      #{run_xml(placeholder, @default_style)}
      <w:r><w:fldChar w:fldCharType="end"/></w:r>
    XML
  end

  def styles_xml
    named_styles = @styles.reject { |name, _| name == 'default' }.map do |name, style|
      outline_level = name.match(/\A標題 ([1-9])\z/) { |m| m[1].to_i - 1 }
      ppr = outline_level ? "<w:pPr><w:outlineLvl w:val=\"#{outline_level}\"/></w:pPr>" : ''
      <<~XML
        <w:style w:type="paragraph" w:styleId="#{escape_xml(name)}">
          <w:name w:val="#{escape_xml(name)}"/>
          <w:basedOn w:val="Normal"/>
          #{ppr}
          #{run_properties_xml(style)}
        </w:style>
      XML
    end.join

    xml_decl(
      <<~XML
        <w:styles xmlns:w="#{W_NS}">
          <w:docDefaults>
            <w:rPrDefault>#{run_properties_xml(@default_style, extra: '<w:noProof/>')}</w:rPrDefault>
            <w:pPrDefault><w:pPr><w:spacing w:after="120"/></w:pPr></w:pPrDefault>
          </w:docDefaults>
          <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
            <w:name w:val="Normal"/>
            <w:qFormat/>
          </w:style>
          <w:style w:type="paragraph" w:styleId="FootnoteText">
            <w:name w:val="footnote text"/>
            <w:basedOn w:val="Normal"/>
            <w:pPr><w:spacing w:after="0"/></w:pPr>
            <w:rPr><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr>
          </w:style>
          <w:style w:type="character" w:styleId="FootnoteReference">
            <w:name w:val="footnote reference"/>
            <w:basedOn w:val="DefaultParagraphFont"/>
            <w:rPr><w:vertAlign w:val="superscript"/></w:rPr>
          </w:style>
          #{named_styles}
        </w:styles>
      XML
    )
  end

  def settings_xml
    xml_decl(
      <<~XML
        <w:settings xmlns:w="#{W_NS}">
          <w:hideSpellingErrors/>
          <w:hideGrammaticalErrors/>
          <w:defaultTabStop w:val="720"/>
          <w:characterSpacingControl w:val="doNotCompress"/>
          <w:compat>
            <w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/>
          </w:compat>
        </w:settings>
      XML
    )
  end

  def font_table_xml
    fonts = (collect_fonts + [WESTERN_FONT]).uniq
    entries = fonts.map do |font|
      <<~XML
        <w:font w:name="#{escape_xml(font)}">
          <w:charset w:val="00"/>
          <w:family w:val="auto"/>
        </w:font>
      XML
    end.join

    xml_decl("<w:fonts xmlns:w=\"#{W_NS}\">#{entries}</w:fonts>")
  end

  def content_types_xml
    image_defaults = media_extensions.map do |extension|
      %(<Default Extension="#{extension}" ContentType="#{IMAGE_CONTENT_TYPES.fetch(extension)}"/>)
    end.join

    xml_decl(
      <<~XML
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          #{image_defaults}
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
          <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
          <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
          <Override PartName="/word/fontTable.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml"/>
          <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
          <Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>
        </Types>
      XML
    )
  end

  def root_relationships_xml
    xml_decl(
      <<~XML
        <Relationships xmlns="#{PKG_REL_NS}">
          <Relationship Id="rId1" Type="#{OFFICE_REL_NS}/officeDocument" Target="word/document.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
          <Relationship Id="rId3" Type="#{OFFICE_REL_NS}/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
      XML
    )
  end

  def document_relationships_xml
    xml_decl(
      <<~XML
        <Relationships xmlns="#{PKG_REL_NS}">
          <Relationship Id="rIdStyles" Type="#{OFFICE_REL_NS}/styles" Target="styles.xml"/>
          <Relationship Id="rIdSettings" Type="#{OFFICE_REL_NS}/settings" Target="settings.xml"/>
          <Relationship Id="rIdFontTable" Type="#{OFFICE_REL_NS}/fontTable" Target="fontTable.xml"/>
          <Relationship Id="rIdFooter" Type="#{OFFICE_REL_NS}/footer" Target="footer1.xml"/>
          <Relationship Id="rIdFootnotes" Type="#{OFFICE_REL_NS}/footnotes" Target="footnotes.xml"/>
          #{image_relationships_xml(:document)}
        </Relationships>
      XML
    )
  end

  def footnotes_relationships_xml
    xml_decl(
      <<~XML
        <Relationships xmlns="#{PKG_REL_NS}">
          #{image_relationships_xml(:footnotes)}
        </Relationships>
      XML
    )
  end

  def core_properties_xml
    now = Time.now.utc.iso8601
    title = text_at('/document/settings/title')
    byline = text_at('/document/settings/byline')

    xml_decl(
      <<~XML
        <cp:coreProperties
          xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
          xmlns:dc="http://purl.org/dc/elements/1.1/"
          xmlns:dcterms="http://purl.org/dc/terms/"
          xmlns:dcmitype="http://purl.org/dc/dcmitype/"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>#{escape_xml(title)}</dc:title>
          <dc:creator>#{escape_xml(byline)}</dc:creator>
          <cp:lastModifiedBy>xml2docx.rb</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">#{now}</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">#{now}</dcterms:modified>
        </cp:coreProperties>
      XML
    )
  end

  def app_properties_xml
    xml_decl(
      <<~XML
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
                    xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
          <Application>xml2docx.rb</Application>
        </Properties>
      XML
    )
  end

  def half_points(value)
    points = font_size_points(value)
    points && (points * 2).round
  end

  def width_xml(value, tag)
    if (pct = percentage_to_ooxml(value))
      "<#{tag} w:w=\"#{pct}\" w:type=\"pct\"/>"
    else
      "<#{tag} w:w=\"0\" w:type=\"auto\"/>"
    end
  end

  def percentage_to_ooxml(value)
    pct = percentage_value(value)
    pct && (pct * 50).round
  end
end
