# frozen_string_literal: true

require 'nokogiri'
require 'time'

# 把 xml4docx 中間格式轉為 odt (ODF text)
#
#   XmlToOdtConverter.new(xml_path, figures_dir: dir).convert(odt_path)
#
# figures_dir 是 CBR2X-figures 的路徑; 未指定時 <graphic> 會退回文字佔位符。
#
# 與 docx 版最大的差別是 ODF 沒有 inline 的格式屬性: 每組格式都要先註冊成
# automatic style, 內容再用名稱引用, 所以有 auto_style_name 這個登記表。
class XmlToOdtConverter
  include Xml4docxSupport

  MIMETYPE = 'application/vnd.oasis.opendocument.text'
  ODF_VERSION = '1.3'

  NAMESPACES = {
    'office' => 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'style' => 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'text' => 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'table' => 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
    'draw' => 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'fo' => 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
    'svg' => 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0',
    'xlink' => 'http://www.w3.org/1999/xlink',
    'meta' => 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0',
    'dc' => 'http://purl.org/dc/elements/1.1/',
    'manifest' => 'urn:oasis:names:tc:opendocument:xmlns:manifest:1.0'
  }.freeze

  DOCUMENT_NAMESPACES = %w[office style text table draw fo svg xlink].freeze
  META_NAMESPACES = %w[office meta dc].freeze

  # A4 直式, 四邊各 2.54cm (與 docx 版相同)
  PAGE_WIDTH_CM = 21.0
  PAGE_HEIGHT_CM = 29.7
  PAGE_MARGIN_CM = 2.54
  CONTENT_WIDTH_CM = PAGE_WIDTH_CM - (PAGE_MARGIN_CM * 2)
  # 圖片以 96 DPI 換算 cm
  CM_PER_PIXEL = 2.54 / 96
  # 圖片最大尺寸: 版面可用寬高
  # 高度留 10% 餘裕, 否則整頁高的圖會把同段落的文字擠到上一頁, 留下大片空白
  MAX_IMAGE_WIDTH_CM = CONTENT_WIDTH_CM
  MAX_IMAGE_HEIGHT_CM = (PAGE_HEIGHT_CM - (PAGE_MARGIN_CM * 2)) * 0.9

  # 對應 docx 的 120 twips 段後距與 720 twips 縮排
  PARAGRAPH_SPACING_CM = 0.212
  LIST_INDENT_CM = 1.27
  TABLE_BORDER = '0.5pt solid #808080'
  TABLE_CELL_PADDING_CM = 0.141

  # 中文字型只套在 asian, 西文另外指定, 否則英文與羅馬轉寫會被中文字型撐開字距
  WESTERN_FONT = 'Times New Roman'
  # 語言標成 zxx (無語言內容), LibreOffice 就不會對內文做拼字與文法檢查
  NO_PROOFING_ATTRIBUTES = 'fo:language="zxx" fo:country="none" ' \
                           'style:language-asian="zxx" style:country-asian="none" ' \
                           'style:language-complex="zxx" style:country-complex="none"'

  DEFAULT_PARAGRAPH_STYLE = 'Standard'
  FOOTNOTE_PARAGRAPH_STYLE = 'Footnote'
  # LibreOffice 內建 character style 的名稱, 空白編碼成 _20_
  FOOTNOTE_SYMBOL_STYLE = 'Footnote_20_Symbol'
  FOOTNOTE_ANCHOR_STYLE = 'Footnote_20_anchor'
  GRAPHIC_PROPERTIES =
    '<style:graphic-properties style:vertical-pos="top" style:vertical-rel="baseline" ' \
    'fo:padding="0cm" fo:border="none"/>'

  def initialize(input_path, figures_dir: nil)
    @input_path = input_path
    @figures_dir = figures_dir
    @xml = Nokogiri::XML(File.read(input_path, encoding: 'UTF-8')) { |config| config.strict }
    @styles = read_styles
    @default_style = @styles.fetch('default', {})
    @default_text_properties = text_properties_xml(@default_style)
    @named_styles = build_named_styles
    @warnings = []
    @images = {}      # url => 圖片資訊 (讀不到時為 nil)
    @pictures = {}    # url => { name:, data:, media_type: }
    @auto_styles = {} # [family, parent, properties] => { name:, ... }
    @auto_style_counts = Hash.new(0)
    @table_count = 0
    @image_count = 0
    @footnote_count = 0
  end

  def convert(output_path)
    OfficeZipWriter.write(output_path, package_parts, stored: ['mimetype'])
    @warnings.uniq
  end

  private

  def package_parts
    # 內容要先產生, 之後才知道用到哪些 automatic style 與圖片
    body = body_xml

    parts = { 'mimetype' => MIMETYPE }
    parts['content.xml'] = content_xml(body)
    parts['styles.xml'] = styles_xml
    parts['meta.xml'] = meta_xml
    @pictures.each_value { |picture| parts["Pictures/#{picture[:name]}"] = picture[:data] }
    parts['META-INF/manifest.xml'] = manifest_xml
    parts
  end

  def build_named_styles
    @styles.keys.reject { |name| name == 'default' }
           .each_with_index.to_h { |name, index| [name, "S#{index + 1}"] }
  end

  # --- content.xml ---

  def body_xml
    body = @xml.at_xpath('/document/body')
    raise "Missing /document/body in #{@input_path}" unless body

    body.element_children.map { |node| block_xml(node) }.join
  end

  def content_xml(body)
    xml_decl(
      <<~XML
        <office:document-content #{namespace_attributes(DOCUMENT_NAMESPACES)} office:version="#{ODF_VERSION}">
          <office:font-face-decls/>
          <office:automatic-styles>#{automatic_styles_xml}</office:automatic-styles>
          <office:body>
            <office:text>#{body}</office:text>
          </office:body>
        </office:document-content>
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
    content = +''
    content << span_xml(prefix, style) if prefix
    content << inline_content_xml(node.children, style)

    paragraph_from_content_xml(content, style, list_context, pstyle: paragraph_style_name(node))
  end

  def paragraph_from_content_xml(content, style, list_context, pstyle: nil)
    name = paragraph_style_reference(style, list_context, pstyle)
    level = heading_level(pstyle)
    return %(<text:h text:outline-level="#{level}" text:style-name="#{name}">#{content}</text:h>) if level

    %(<text:p text:style-name="#{name}">#{content}</text:p>)
  end

  def heading_level(name)
    name.to_s.match(/\A標題 ([1-9])\z/) { |match| match[1].to_i }
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

  # --- table ---

  def table_xml(node, inherited_style: nil)
    style = merge_styles(inherited_style, style_for(node))
    rows = node.xpath('./row').to_a
    column_count = table_column_count(node, rows)
    width = table_width_cm(style)
    @table_count += 1

    <<~XML
      <table:table table:name="Table#{@table_count}" table:style-name="#{table_style_name(width)}">
        <table:table-column table:style-name="#{table_column_style_name(width / column_count)}" table:number-columns-repeated="#{column_count}"/>
        #{table_rows_xml(rows, style)}
      </table:table>
    XML
  end

  def table_width_cm(style)
    percentage = percentage_value(style['width'])
    percentage ? CONTENT_WIDTH_CM * percentage / 100 : CONTENT_WIDTH_CM
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
        # 跨列的儲存格在後續各列都要補上等量的 covered cell
        cells << covered_cells_xml(span[:cols])
        span[:remaining_rows] -= 1
        active_spans.delete(column) if span[:remaining_rows].zero?
        column += span[:cols]
        next
      end

      if cell_index < source_cells.length
        cell = source_cells[cell_index]
        cols = positive_integer(cell['cols'], 1)
        rows = positive_integer(cell['rows'], 1)

        cells << cell_xml(cell, table_style, cols, rows)
        cells << covered_cells_xml(cols - 1)
        active_spans[column] = { cols: cols, remaining_rows: rows - 1 } if rows > 1
        column += cols
        cell_index += 1
        next
      end

      cells << empty_cell_xml
      column += 1
    end

    "<table:table-row>#{cells}</table:table-row>"
  end

  def covered_cells_xml(count)
    '<table:covered-table-cell/>' * [count, 0].max
  end

  def cell_xml(node, table_style, cols, rows)
    style = merge_styles(table_style, style_for(node))
    content = cell_content_xml(node, style)
    content = '<text:p/>' if content.empty?

    attributes = +%( table:style-name="#{cell_style_name(style)}" office:value-type="string")
    attributes << %( table:number-columns-spanned="#{cols}") if cols > 1
    attributes << %( table:number-rows-spanned="#{rows}") if rows > 1

    "<table:table-cell#{attributes}>#{content}</table:table-cell>"
  end

  def empty_cell_xml
    %(<table:table-cell table:style-name="#{cell_style_name({})}" office:value-type="string"><text:p/></table:table-cell>)
  end

  def cell_content_xml(node, style)
    return cell_inline_paragraph_xml(node.children, style) unless node.at_xpath('./p')

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
    content = inline_content_xml(nodes, style)
    return '' if content.empty?

    paragraph_from_content_xml(content, style, nil)
  end

  # --- inline ---

  def inline_content_xml(nodes, inherited_style)
    nodes.map do |node|
      case node
      when Nokogiri::XML::Text
        text = normalize_text(node.text)
        text.empty? ? '' : span_xml(text, inherited_style)
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
      '<text:line-break/>'
    when 'seg', 'p'
      inline_content_xml(node.children, merge_styles(inherited_style, style_for(node)))
    when 'font'
      style = merge_styles(inherited_style, style_for(node))
      style = merge_styles(style, 'font-family' => font_name_for(node['name'])) if node['name'].present?
      inline_content_xml(node.children, style)
    when 'footnote'
      footnote_xml(node, inherited_style)
    when 'graphic'
      graphic_xml(node, inherited_style)
    else
      warn_once("Skipping unsupported inline element <#{node.name}>.")
      ''
    end
  end

  def span_xml(text, style)
    styled_span_xml(escape_text(text), style)
  end

  # content 已是 ODF 標記, 只負責套字元樣式
  def styled_span_xml(content, style)
    name = text_style_name(style)
    return content if name.nil?

    %(<text:span text:style-name="#{name}">#{content}</text:span>)
  end

  # ODF 沒有 xml:space="preserve", 連續空白要用 <text:s>
  def escape_text(text)
    escaped = escape_xml(text).gsub("\t", '<text:tab/>')
    escaped.gsub(/ {2,}/) { |spaces| %( <text:s text:c="#{spaces.length - 1}"/>) }
  end

  # --- 註腳 ---

  # ODF 的註腳就地展開, 不需要獨立的 part, 圖片也直接沿用 Pictures/
  def footnote_xml(node, inherited_style)
    @footnote_count += 1
    style = merge_styles(@default_style, 'font-size' => '10')

    note = "<text:note text:id=\"ftn#{@footnote_count}\" text:note-class=\"footnote\">" \
           "<text:note-citation>#{@footnote_count}</text:note-citation>" \
           "<text:note-body>#{footnote_blocks_xml(node, style)}</text:note-body>" \
           '</text:note>'

    # 注標跟著被注內容的字級, 否則夾注小字的注標會被段落標題的大字撐大
    styled_span_xml(note, footnote_reference_style(node, inherited_style))
  end

  # 註腳通常只有一段文字, 但可能夾雜 table; table 不能包在 text:p 裡, 必須拆成多個 block
  def footnote_blocks_xml(node, style)
    blocks = +''

    footnote_groups(node.children).each do |kind, value|
      if kind == :table
        blocks << table_xml(value, inherited_style: style)
      else
        content = inline_content_xml(value, style)
        # 註腳編號與內容之間空一格, 與 docx 版一致
        blocks << footnote_paragraph_xml(content, leading_space: blocks.empty?) unless content.empty?
      end
    end

    # note-body 至少要有一個段落
    blocks.empty? ? footnote_paragraph_xml('') : blocks
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

  def footnote_paragraph_xml(content, leading_space: false)
    space = leading_space ? '<text:s/>' : ''

    %(<text:p text:style-name="#{FOOTNOTE_PARAGRAPH_STYLE}">#{space}#{content}</text:p>)
  end

  # --- 圖片 ---

  def graphic_xml(node, inherited_style)
    url = node['url'].to_s
    image = image_for(url)
    return span_xml("[image: #{url}]", inherited_style) if image.nil?

    frame_xml(url, image)
  end

  def frame_xml(url, image)
    picture = register_picture(url, image)
    width, height = image_extent_cm(image)
    @image_count += 1

    "<draw:frame draw:style-name=\"#{graphic_style_name}\" draw:name=\"Image#{@image_count}\" " \
      "text:anchor-type=\"as-char\" svg:width=\"#{format_length(width)}cm\" " \
      "svg:height=\"#{format_length(height)}cm\" draw:z-index=\"0\">" \
      "<draw:image xlink:href=\"Pictures/#{picture[:name]}\" xlink:type=\"simple\" xlink:show=\"embed\" " \
      "xlink:actuate=\"onLoad\" draw:mime-type=\"#{picture[:media_type]}\"/>" \
      '</draw:frame>'
  end

  # 同一張圖在本文與註腳共用一份 Pictures 檔
  def register_picture(url, image)
    @pictures[url] ||= {
      name: "image#{@pictures.size + 1}.#{image[:extension]}",
      data: image[:data],
      media_type: IMAGE_CONTENT_TYPES.fetch(image[:extension])
    }
  end

  # 等比縮到版面可用範圍內
  def image_extent_cm(image)
    width = image[:width] * CM_PER_PIXEL
    height = image[:height] * CM_PER_PIXEL
    scale = [1.0, MAX_IMAGE_WIDTH_CM / width, MAX_IMAGE_HEIGHT_CM / height].min

    [width * scale, height * scale]
  end

  def graphic_style_name
    @graphic_style_name ||= auto_style_name('graphic', 'fr', GRAPHIC_PROPERTIES)
  end

  # --- automatic style ---

  def auto_style_name(family, prefix, properties, parent: nil)
    key = [family, parent, properties]
    entry = @auto_styles[key] ||= begin
      @auto_style_counts[family] += 1
      { name: "#{prefix}#{@auto_style_counts[family]}", family: family, parent: parent, properties: properties }
    end

    entry[:name]
  end

  def automatic_styles_xml
    @auto_styles.each_value.map do |entry|
      parent = entry[:parent] ? %( style:parent-style-name="#{entry[:parent]}") : ''
      <<~XML
        <style:style style:name="#{entry[:name]}" style:family="#{entry[:family]}"#{parent}>
          #{entry[:properties]}
        </style:style>
      XML
    end.join
  end

  def paragraph_style_reference(style, list_context, pstyle)
    # rend="default" 沒有對應的具名 style, 退回預設段落樣式
    parent = @named_styles.fetch(pstyle, DEFAULT_PARAGRAPH_STYLE)
    properties = paragraph_properties_xml(style, list_context)
    return parent if properties.empty?

    auto_style_name('paragraph', 'P', properties, parent: parent)
  end

  def text_style_name(style)
    properties = text_properties_xml(merge_styles(@default_style, style))
    return nil if properties.empty? || properties == @default_text_properties

    auto_style_name('text', 'T', properties)
  end

  def table_style_name(width)
    properties = %(<style:table-properties style:width="#{format_length(width)}cm" table:align="left" style:writing-mode="page"/>)

    auto_style_name('table', 'Ta', properties)
  end

  # LibreOffice 只認絕對欄寬, style:rel-column-width 會被忽略
  def table_column_style_name(width)
    auto_style_name('table-column', 'Tc', %(<style:table-column-properties style:column-width="#{format_length(width)}cm"/>))
  end

  def cell_style_name(style)
    attributes = [%(fo:border="#{TABLE_BORDER}"), %(fo:padding="#{format_length(TABLE_CELL_PADDING_CM)}cm")]
    if (fill = odf_color(style['background-color']))
      attributes << %(fo:background-color="#{fill}")
    end

    auto_style_name('table-cell', 'Tb', %(<style:table-cell-properties #{attributes.join(' ')}/>))
  end

  def paragraph_properties_xml(style, list_context)
    attributes = []

    if (alignment = odf_alignment(style['text-align'] || style['cell-align']))
      attributes << %(fo:text-align="#{alignment}" style:justify-single-word="false")
    end

    if (fill = odf_color(style['background-color']))
      attributes << %(fo:background-color="#{fill}")
    end

    if list_context
      indent = [list_context[:level], 1].max * LIST_INDENT_CM
      attributes << %(fo:margin-left="#{format_length(indent)}cm")
    end

    attributes.empty? ? '' : %(<style:paragraph-properties #{attributes.join(' ')}/>)
  end

  # ODF 的西文/中日韓/複雜文種字型與大小是分開的屬性, 三者都要設才會一致
  # extra 是額外的 text-properties 屬性字串
  def text_properties_xml(style, extra: nil)
    attributes = []

    if (font = style['font-family'])
      asian = escape_xml(quote_font_family(font))
      western = escape_xml(quote_font_family(font.match?(/\p{Han}/) ? WESTERN_FONT : font))
      attributes << %(fo:font-family="#{western}" style:font-family-asian="#{asian}" style:font-family-complex="#{western}")
    end

    if (points = font_size_points(style['font-size']))
      size = "#{format_length(points)}pt"
      attributes << %(fo:font-size="#{size}" style:font-size-asian="#{size}" style:font-size-complex="#{size}")
    end

    if bold?(style['font-weight'])
      attributes << 'fo:font-weight="bold" style:font-weight-asian="bold" style:font-weight-complex="bold"'
    end

    attributes << %(fo:color="#{odf_color(style['color'])}") if odf_color(style['color'])
    attributes << %(fo:background-color="#{odf_color(style['background-color'])}") if odf_color(style['background-color'])

    attributes << extra if extra

    attributes.empty? ? '' : %(<style:text-properties #{attributes.join(' ')}/>)
  end

  # --- styles.xml ---

  def styles_xml
    xml_decl(
      <<~XML
        <office:document-styles #{namespace_attributes(DOCUMENT_NAMESPACES)} office:version="#{ODF_VERSION}">
          <office:font-face-decls/>
          <office:styles>
            #{default_style_xml}
            <style:style style:name="#{DEFAULT_PARAGRAPH_STYLE}" style:family="paragraph" style:class="text"/>
            <style:style style:name="#{FOOTNOTE_PARAGRAPH_STYLE}" style:family="paragraph" style:parent-style-name="#{DEFAULT_PARAGRAPH_STYLE}" style:class="extra">
              <style:paragraph-properties fo:margin-bottom="0cm" fo:text-indent="0cm"/>
              <style:text-properties fo:font-size="10pt" style:font-size-asian="10pt" style:font-size-complex="10pt"/>
            </style:style>
            <style:style style:name="#{FOOTNOTE_SYMBOL_STYLE}" style:display-name="Footnote Symbol" style:family="text">
              <style:text-properties style:text-position="super 58%"/>
            </style:style>
            <style:style style:name="#{FOOTNOTE_ANCHOR_STYLE}" style:display-name="Footnote anchor" style:family="text">
              <style:text-properties style:text-position="super 58%"/>
            </style:style>
            <text:notes-configuration text:note-class="footnote" text:default-style-name="#{FOOTNOTE_PARAGRAPH_STYLE}" text:citation-style-name="#{FOOTNOTE_SYMBOL_STYLE}" text:citation-body-style-name="#{FOOTNOTE_ANCHOR_STYLE}" style:num-format="1" text:start-value="0" text:footnotes-position="page" text:start-numbering-at="document"/>
            #{named_styles_xml}
          </office:styles>
          <office:automatic-styles>
            #{page_layout_xml}
            <style:style style:name="MP1" style:family="paragraph" style:parent-style-name="#{DEFAULT_PARAGRAPH_STYLE}">
              <style:paragraph-properties fo:text-align="center" style:justify-single-word="false"/>
            </style:style>
          </office:automatic-styles>
          <office:master-styles>
            <style:master-page style:name="#{DEFAULT_PARAGRAPH_STYLE}" style:page-layout-name="pm1">
              <style:footer>#{footer_paragraph_xml}</style:footer>
            </style:master-page>
          </office:master-styles>
        </office:document-styles>
      XML
    )
  end

  def default_style_xml
    <<~XML
      <style:default-style style:family="paragraph">
        <style:paragraph-properties fo:margin-bottom="#{format_length(PARAGRAPH_SPACING_CM)}cm" style:writing-mode="lr-tb"/>
        #{text_properties_xml(@default_style, extra: NO_PROOFING_ATTRIBUTES)}
      </style:default-style>
    XML
  end

  # style:name 不能有空白等字元, 用產生的名稱, 原名放 display-name
  def named_styles_xml
    @named_styles.map do |source_name, odt_name|
      level = heading_level(source_name)
      outline = level ? %( style:default-outline-level="#{level}") : ''
      properties = text_properties_xml(merge_styles(@default_style, @styles.fetch(source_name)))

      <<~XML
        <style:style style:name="#{odt_name}" style:family="paragraph" style:parent-style-name="#{DEFAULT_PARAGRAPH_STYLE}" style:display-name="#{escape_xml(source_name)}"#{outline}>
          #{properties}
        </style:style>
      XML
    end.join
  end

  def page_layout_xml
    <<~XML
      <style:page-layout style:name="pm1">
        <style:page-layout-properties fo:page-width="#{format_length(PAGE_WIDTH_CM)}cm" fo:page-height="#{format_length(PAGE_HEIGHT_CM)}cm" style:print-orientation="portrait" fo:margin-top="#{format_length(PAGE_MARGIN_CM)}cm" fo:margin-bottom="#{format_length(PAGE_MARGIN_CM)}cm" fo:margin-left="#{format_length(PAGE_MARGIN_CM)}cm" fo:margin-right="#{format_length(PAGE_MARGIN_CM)}cm" style:writing-mode="lr-tb">
          <style:footnote-sep style:width="0.018cm" style:distance-before-sep="0.101cm" style:distance-after-sep="0.101cm" style:line-style="solid" style:adjustment="left" style:rel-width="25%" style:color="#000000"/>
        </style:page-layout-properties>
        <style:header-style/>
        <style:footer-style>
          <style:header-footer-properties fo:min-height="1.27cm" fo:margin-top="0.5cm" style:dynamic-spacing="false"/>
        </style:footer-style>
      </style:page-layout>
    XML
  end

  def footer_paragraph_xml
    footer = text_at('/document/settings/footer')
    content = footer.to_s.split(/(\{Page\}|\{NumPages\})/).map do |part|
      case part
      when '{Page}'
        '<text:page-number text:select-page="current">1</text:page-number>'
      when '{NumPages}'
        '<text:page-count>1</text:page-count>'
      else
        escape_text(part)
      end
    end.join

    %(<text:p text:style-name="MP1">#{content}</text:p>)
  end

  # --- meta.xml / manifest ---

  def meta_xml
    now = Time.now.utc.iso8601
    title = text_at('/document/settings/title')
    byline = text_at('/document/settings/byline')

    xml_decl(
      <<~XML
        <office:document-meta #{namespace_attributes(META_NAMESPACES)} office:version="#{ODF_VERSION}">
          <office:meta>
            <dc:title>#{escape_xml(title)}</dc:title>
            <meta:initial-creator>#{escape_xml(byline)}</meta:initial-creator>
            <dc:creator>#{escape_xml(byline)}</dc:creator>
            <meta:creation-date>#{now}</meta:creation-date>
            <dc:date>#{now}</dc:date>
            <meta:generator>xml2odt.rb</meta:generator>
          </office:meta>
        </office:document-meta>
      XML
    )
  end

  def manifest_xml
    pictures = @pictures.each_value.map do |picture|
      %(<manifest:file-entry manifest:full-path="Pictures/#{picture[:name]}" manifest:media-type="#{picture[:media_type]}"/>)
    end.join

    xml_decl(
      <<~XML
        <manifest:manifest xmlns:manifest="#{NAMESPACES.fetch('manifest')}" manifest:version="#{ODF_VERSION}">
          <manifest:file-entry manifest:full-path="/" manifest:version="#{ODF_VERSION}" manifest:media-type="#{MIMETYPE}"/>
          <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
          <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
          <manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/>
          #{pictures}
        </manifest:manifest>
      XML
    )
  end

  # --- 小工具 ---

  def namespace_attributes(prefixes)
    prefixes.map { |prefix| %(xmlns:#{prefix}="#{NAMESPACES.fetch(prefix)}") }.join(' ')
  end

  def odf_alignment(value)
    case alignment_value(value)
    when 'center' then 'center'
    when 'right' then 'end'
    when 'left' then 'start'
    end
  end

  def odf_color(value)
    color = color_value(value)
    color && "##{color}"
  end

  # 含空白的字型名稱在 fo:font-family 要加單引號
  def quote_font_family(font)
    font.include?(' ') ? "'#{font}'" : font
  end

  def format_length(value)
    rounded = value.round(3)
    rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
  end
end
