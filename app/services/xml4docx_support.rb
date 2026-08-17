# frozen_string_literal: true

require 'cgi/escape'

# xml4docx 中間格式的共用處理: style 解析、table 跨欄跨列計算、圖片讀取。
# 由 XmlToDocxConverter 與 XmlToOdtConverter 共用。
#
# include 的 class 必須在 initialize 準備好這些 ivar:
#   @xml (Nokogiri::XML::Document)、@figures_dir、@images ({})、@warnings ([])
module Xml4docxSupport
  GIF_SIGNATURES = ['GIF87a'.b, 'GIF89a'.b].freeze
  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze
  JPEG_SIGNATURE = "\xff\xd8".b.freeze

  IMAGE_CONTENT_TYPES = {
    'gif' => 'image/gif',
    'png' => 'image/png',
    'jpg' => 'image/jpeg',
    'jpeg' => 'image/jpeg'
  }.freeze

  private

  # --- style ---

  def read_styles
    @xml.xpath('/document/settings/styles/style').each_with_object({}) do |style_node, styles|
      styles[style_node['name'].to_s] = parse_style(style_node.text)
    end
  end

  def style_for(node)
    merge_styles(named_style(node['rend']), parse_style(node['style']))
  end

  def named_style(name)
    return {} if name.nil? || name.empty?
    return @styles[name] if @styles.key?(name)

    name.split(/\s+/).each_with_object({}) do |part, style|
      style.merge!(@styles[part]) if @styles.key?(part)
    end
  end

  def parse_style(value)
    value.to_s.split(';').each_with_object({}) do |declaration, style|
      key, property_value = declaration.split(':', 2).map { |part| part&.strip }
      next if key.nil? || key.empty? || property_value.nil? || property_value.empty?

      style[key.downcase] = property_value
    end
  end

  def merge_styles(*styles)
    styles.compact.each_with_object({}) { |style, merged| merged.merge!(style) }
  end

  # rend 可能是多個名稱, 取第一個有定義的當段落 style
  def paragraph_style_name(node)
    rend = node['rend'].to_s.strip
    return rend if @styles.key?(rend)

    rend.split(/\s+/).find { |part| @styles.key?(part) }
  end

  # --- table 跨欄跨列 ---

  def table_column_count(node, rows)
    explicit = positive_integer(node['cols'], 0)
    inferred = inferred_table_column_count(rows)

    [explicit, inferred, 1].max
  end

  def inferred_table_column_count(rows)
    active_spans = {}

    rows.map do |row|
      measure_row_column_count(row, active_spans)
    end.max || 1
  end

  def measure_row_column_count(node, active_spans)
    source_cells = node.xpath('./cell').to_a
    cell_index = 0
    column = 0

    while cell_index < source_cells.length || active_span_at_or_after?(active_spans, column)
      if (span = active_spans[column])
        span[:remaining_rows] -= 1
        active_spans.delete(column) if span[:remaining_rows].zero?
        column += span[:cols]
        next
      end

      if cell_index < source_cells.length
        cell = source_cells[cell_index]
        cols = positive_integer(cell['cols'], 1)
        rows = positive_integer(cell['rows'], 1)

        active_spans[column] = { cols: cols, remaining_rows: rows - 1 } if rows > 1
        column += cols
        cell_index += 1
        next
      end

      column += 1
    end

    column
  end

  def active_span_at_or_after?(active_spans, column)
    active_spans.keys.any? { |active_column| active_column >= column }
  end

  # --- 圖片 ---

  # 讀不到的圖片也快取為 nil, 避免同一份 XML 重複讀檔
  def image_for(url)
    return @images[url] if @images.key?(url)

    @images[url] = read_image(url)
  end

  def read_image(url)
    if @figures_dir.nil?
      warn_once('figures_dir is not set; graphics are rendered as text placeholders.')
      return nil
    end

    path = File.join(@figures_dir, url)
    unless File.file?(path)
      warn_once("Missing image file: #{url}")
      return nil
    end

    data = File.binread(path)
    size = image_pixel_size(data)
    extension = File.extname(url).downcase.delete_prefix('.')
    unless size && IMAGE_CONTENT_TYPES.key?(extension)
      warn_once("Unsupported image format: #{url}")
      return nil
    end

    { data: data, width: size[0], height: size[1], extension: extension }
  end

  def image_pixel_size(data)
    if GIF_SIGNATURES.any? { |signature| data.start_with?(signature) }
      data[6, 4].unpack('v2')
    elsif data.start_with?(PNG_SIGNATURE)
      data[16, 8].unpack('N2')
    elsif data.start_with?(JPEG_SIGNATURE)
      jpeg_pixel_size(data)
    end
  end

  # 掃 JPEG 的 SOFn marker 取得尺寸
  def jpeg_pixel_size(data)
    offset = 2

    while offset < data.bytesize - 9
      break unless data.getbyte(offset) == 0xff

      marker = data.getbyte(offset + 1)
      length = data[offset + 2, 2].unpack1('n').to_i
      # SOF0..SOF15, 但不含 DHT(c4) / JPGA(c8) / DAC(cc)
      return data[offset + 5, 4].unpack('n2').reverse if (0xc0..0xcf).cover?(marker) && ![0xc4, 0xc8, 0xcc].include?(marker)

      offset += 2 + length
    end

    nil
  end

  # --- list ---

  def list_marker(type, index)
    case type
    when 'none'
      nil
    when 'decimal', 'number', 'ordered'
      "#{index + 1}. "
    else
      '• '
    end
  end

  # --- 其他 ---

  def normalize_text(text)
    text.gsub(/\r?\n[ \t]*/, '')
  end

  def text_at(xpath)
    @xml.at_xpath(xpath)&.text.to_s
  end

  def positive_integer(value, fallback)
    integer = value.to_i
    integer.positive? ? integer : fallback
  end

  def alignment_value(value)
    case value.to_s.downcase
    when 'center', 'centre'
      'center'
    when 'right', 'end'
      'right'
    when 'left', 'start'
      'left'
    end
  end

  def font_size_points(value)
    return nil if value.nil? || value.to_s.empty?

    points = Float(value)
    points.positive? ? points : nil
  rescue ArgumentError
    nil
  end

  def bold?(value)
    %w[bold 700 800 900].include?(value.to_s.downcase)
  end

  # 回傳 6 碼大寫 hex, 不含 #
  def color_value(value)
    color = value.to_s.strip.delete_prefix('#')
    return nil unless color.match?(/\A[0-9a-fA-F]{6}\z/)

    color.upcase
  end

  def percentage_value(value)
    return nil unless value.to_s.end_with?('%')

    pct = Float(value.to_s.chomp('%'))
    pct.negative? ? nil : pct
  rescue ArgumentError
    nil
  end

  def collect_fonts
    fonts = @styles.values.filter_map { |style| style['font-family'] }
    fonts += @xml.xpath('//font[@name]').map { |node| node['name'] }
    fonts.uniq
  end

  def escape_xml(value)
    CGI.escapeHTML(value.to_s)
  end

  def xml_decl(body)
    %(<?xml version="1.0" encoding="UTF-8"?>\n#{body})
  end

  def warn_once(message)
    @warnings << message
  end
end
