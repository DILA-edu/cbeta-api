# 將 CBETA XML 簡化為適合轉換成 docx 的 XML 格式 (xml4docx)

require_relative 'css_parser'
require_relative 'cbeta-module'
require_relative 'cbeta_p5a_share'
require_relative 'html-node'
require_relative 'share'

class XMLForDocx1
  include CBETAModule

  PASS = %w[figDesc teiHeader mulu rdg]

  def initialize(src, dest)
    @xml_root = src
    @git = Git.open(@xml_root)
    @dest_root = dest
    @cbeta = CBETA.new
    @gaiji = CBETA::Gaiji.new
    @my_cbeta_share = MyCbetaShare.new

    fn = Rails.root.join('lib', 'tasks', 'xml4docx-styles.yaml')
    @predefined_styles = YAML.load_file(fn)
  end
  
  def convert(publish, canon)
    @publish = publish
    @pre_max = { work: '', text: '' }

    if canon.nil?
      each_canon(@xml_root) do |c|
        convert_canon(c)
      end
    else
      convert_canon(canon)
    end

    #puts "最長的 pre 內容是 #{@pre_max[:work]}: #{@pre_max[:text].size} 字"
    #puts @pre_max[:text]
  end

  def convert_canon(canon)
    puts canon
    @canon = canon
    @orig = @cbeta.get_canon_symbol(@canon)
    @canon_name = @my_cbeta_share.get_canon_name(canon)
    read_authority_catalog

    src = File.join(@xml_root, @canon)
    Dir.glob("*", base: src, sort: true) do |f|
      convert_vol(f)
    end
  end

  private

  def convert_vol(vol)
    puts "xml4docx1 #{vol}"
    @vol = vol
    src = File.join(@xml_root, @canon, vol)
    Dir.glob("*.xml", base: src, sort: true) do |f|
      convert_file(f)
    end
    puts
  end

  def copy_style(e, node)
    if e["rend"]
      abort "rend 與 type 同時存在, tag: #{e.name}" if e['type']
      rend = e['rend']
      rend = "table_#{rend}" if e.name == 'table'
      node["rend"] = rend
      @styles << rend
    elsif e["type"]
      rend = e['type']
      if not %w[dharani xx].include?(rend)
        node['rend'] = rend
        @styles << rend
      end
    end
    
    if e["style"]
      rend = CSSParser.new(e["style"]).to_class
      Rails.logger.info "style: #{e["style"]}, class: #{rend}"
      if rend.nil? or node.attributes.key?("rend")
        node["style"] = e["style"] 
      else
        rend = "table_#{rend}" if e.name == 'table'
        node["rend"] = rend
        @styles << rend
      end
    end
  end

  def convert_file(fn)
    @v_work = File.basename(fn, '.xml')
    @v_work.sub!(/^(T\d\dn0220)(.*)$/, '\1')
    @work = CBETA.get_work_id_from_file_basename(@v_work)
    
    print "\rconvert_file: #{fn}   "
    src = File.join(@xml_root, @canon, @vol, fn)
    @updated_at = cb_xml_updated_at(path: src)

    @dest_folder = File.join(@dest_root, @canon, @vol, @v_work)
    FileUtils.makedirs(@dest_folder)
    doc = File.open(src) { |f| Nokogiri::XML(f) }
    doc.remove_namespaces!
    @source_desc = get_source_desc(doc)

    e = doc.at_xpath("//projectDesc/p[@lang='zh-Hant']")
    abort "找不到貢獻者" if e.nil?
    @contributors = e.text

    init_juan
    read_mod_notes(doc)
    @div_level = 0
    @list_level = 0
    @next_line_buf = ''
    @juan = 0
    @in_lg = false
    @pre = [false]
    @seg = []
    traverse(doc.root)
    write_juan
  end

  def e_anchor(e)
    if e.has_attribute?('id')
      id = e['id']
      if id.start_with? 'fx'
        return "[＊]"
      end
    end

    if e.has_attribute?('type')
      if e['type'] == 'circle'
        return '◎'
      end
    end

    ''
  end

  def e_byline(e)
    @styles << "byline"
    node = HTMLNode.new('p')
    node["rend"] = "byline"
    node.content = traverse(e)
    node.to_s + "\n"
  end

  def e_caesura(e)
    i = 2

    if e.key?('style')
      e['style'].match(/text-indent: ?(\d+)em/) do
        i = $1.to_i
      end
    end

    '　' * i
  end

  def e_cell(e)
    node = HTMLNode.new('cell')
    node['cols'] = e['cols'] if e['cols']
    node['rows'] = e['rows'] if e['rows']
    copy_style(e, node)
    node.content = traverse(e)
    node.to_s + "\n"
  end

  def e_div(e)
    @div_level += 1
    traverse(e)
    @div_level -= 1
    ""
  end

  def e_doc_number(e)
    node = HTMLNode.new('p')
    node.content = traverse(e)
    node.to_s + "\n"
  end

  def e_form(e)
    abort "form 的 parent 不是 entry" unless e.parent.name == 'entry'
    @styles << "entry_form"

    node = HTMLNode.new('p')
    node["rend"] = "entry_form"
    node.content = traverse(e)
    node.to_s + "\n"
  end

  # Basic Multilingual Plane, U+0000 - U+FFFF[3]
  # Supplementary Ideographic Plane, U+20000 - U+2FFFF
  #   Extension B: U+20000..U+2A6DF
  #   Extension C: U+2A700..U+2B73F
  def e_g(e)
    skt_priority = %w(symbol romanized)
    id = e["ref"].delete_prefix("#")
    r = @gaiji.to_s(id, skt_priority:)

    if r.nil?
      # 如果沒有羅馬轉寫就顯示圖檔
      r = 
        case id
        when /^SD/
          url = File.join('sd-gif', id[3, 2], "#{id}.gif")
          "<graphic url='#{url}'/>"
        when /^RJ/
          url = File.join('rj-gif', id[3, 2], "#{id}.gif")
          "<graphic url='#{url}'/>"
        end
    else
      if r.size == 1 and id.start_with?('CB')
        r = handle_char(r)
      end
    end
    r
  end

  def e_graphic(e)
    url = e['url'].delete_prefix('../figures/')
    "<graphic url='#{url}'/>"
  end

  def e_head(e)
    unless e.parent.name == 'div'
      return "<p>%s</p>" % traverse(e)
    end

    if @div_level > 9
      return "<p>%s</p>" % traverse(e)
    end

    style = "標題 #{@div_level}"
    @styles << style

    node = HTMLNode.new('p')
    node["rend"] = style
    node.content = traverse(e)
    node.to_s + "\n"
  end

  def e_hi(e)
    node = HTMLNode.new('seg')
    copy_style(e, node)
    node.content = traverse(e)
    node.to_s + "\n"
  end

  def e_item(e)
    node = HTMLNode.new('item')
    node.content = traverse(e)
    r = "\n"
    r << "  " * @list_level
    r << node.to_s
    r
  end

  def e_juan(e)
    @styles << "juan"
    node = HTMLNode.new('p')
    node["rend"] = "juan"
    node.content = traverse(e)
    node.to_s + "\n"
  end

  def e_l(e)
    r = ''
    
    if @first_l
      @first_l = false
    else
      r << "<lb/>\n"
    end

    r << traverse(e)
    r
  end

  def e_lb(e)
    @lb = e['n']

    r = ''
    if @next_line_buf.empty?
      r << '<lb/>' if @pre.last
    else
      r << "<lb/>\n"
      r << @next_line_buf
      r << "<lb/>\n"
      @next_line_buf = ''
    end

    
    r
  end

  def e_lem(e)
    content = traverse(e)
    return content if @canon=='Y' or @canon=='TX'
    return '' if content.empty?

    wit = e['wit']
    if (not wit.nil?) and wit.include? '【CB】' and not wit.include? @orig
      return "<font style='color:#ff0000'>%s</font>" % content
    else
      return content
    end
  end

  def e_lg(e)
    @styles << 'lg'
    @in_lg = true
    @first_l = true
    node = HTMLNode.new('p')
    node['rend'] = 'lg'
    node['style'] = e['style'] if e.key?('style')
    
    s = traverse(e)
    s.gsub!(/　+(<lb\/>)/, '\1')
    s.sub!(/　+$/, '')
    node.content = s

    @in_lg = false
    return node.to_s + "\n"
  end

  def e_list(e)
    @list_level += 1
    node = HTMLNode.new('list')
    node['level'] = @list_level
    node['type'] = 'none' if e['rend'] == 'no-marker'
    node.content = traverse(e)
    @list_level -= 1
    r = node.to_s
    indent = "  " * @list_level
    r.gsub!(/<\/item><\/list>/, "</item>\n#{indent}</list>")
    r
  end

  def e_milestone(e)
    return "" unless e["unit"] == "juan"
    write_juan
    @juan = e["n"].to_i
    ""
  end

  # todo: Y26n0026_p0021a01
  def e_note(e)
    return '' if e['rend'] == 'hide'
    
    if e["place"] == "inline"
      @styles << "inline_note"
      return '<seg rend="inline_note">(%s)</seg>' % traverse(e)
    end

    case e["type"]
    when "add", "mod"
      "<footnote>%s</footnote>" % traverse(e)
    when "orig"
      n = e['n']
      return '' if @mod_notes.include?(n)
      "<footnote>%s</footnote>" % traverse(e)
    else
      ""
    end
  end

  def e_p(e)
    @pre << true if e['type'] == 'pre'
    node = HTMLNode.new('p')
    copy_style(e, node)
    node.content = traverse(e)
    if e['type'] == 'pre'
      @pre.pop
      e_p_pre(node)
    else
      unless @next_line_buf.empty?
        node.content << "<lb/>\n"
        node.content << @next_line_buf
        @next_line_buf = ''
      end  
    end
    node.to_s + "\n"
  end

  def e_p_pre(node)
    node.content.split('<lb/>').each do |s|
      s.gsub!(/<footnote>.*?<\/footnote>/, '')
      s.gsub!(/<[^>]+>/, '')
      if s.size > @pre_max[:text].size
        @pre_max = {
          work: @v_work,
          text: s
        }
      end
    end
  end

  def e_row(e)
    node = HTMLNode.new('row')
    copy_style(e, node)
    node.content = traverse(e)
    node.to_s + "\n"
  end

  def e_seg(e)
    abort "rend 與 style 同時存在" if e.key?("rend") and e.key?("style")
    node = HTMLNode.new('seg')
    copy_style(e, node)
    node.content = traverse(e)
    node.to_s + "\n"
  end

  def e_t(e)
    if e.has_attribute? 'place'
      return '' if e['place'].include? 'foot'
    end

    r = traverse(e)

    tt = e.at_xpath('ancestor::tt')
    unless tt.nil?
      return r if %w(app single-line).include? tt['type']
      return r if tt['rend'] == 'normal'
    end

    if e.key? 'style'
      s = e['style']
      if s =~ /^margin-left: ?(\d+)em$/
        i = $1.to_i
        r = '　' * i + r if i > 0
      else
        r = "<seg style='#{e['style']}'>#{r}</seg>"
      end
    end

    return r if tt['place'] == 'inline'

    # 處理雙行對照
    # <tt type="tr"> 也是 雙行對照
    i = e.xpath('../t').index(e)
    case i
    when 0
      return r + '　'
    when 1
      @next_line_buf << r + '　'
      return ''
    else
      return r
    end
  end

  def e_table(e)
    node = HTMLNode.new('table')
    node['cols'] = e['cols'] if e['cols']
    copy_style(e, node)
    node.content = traverse(e)
    node.to_s + "\n"
  end

  def e_unclear(e)
    r = traverse(e)
    r = '▆' if r.empty?
    r
  end

  def handle_char(char)
    code = char.codepoints.first
    
    if (0x0000..0xFFFF).include?(code)
      return char.encode(xml: :text)
    end

    if (0x20000..0x2A6DF).include?(code)
      r = "<font name=\"hana_b\">#{char}</font>"
    elsif (0x2A700..0x2FFFF).include?(code)
      r = "<font name=\"hana_c\">#{char}</font>"
    else
      abort "未知 unicode: %X, lb: #{@lb}" % code
    end
  end

  def handle_node(node)
    return "" if node.comment?
    return handle_text(node) if node.text?
    return "" if PASS.include?(node.name)

    case node.name
    when 'anchor' then e_anchor(node)
    when 'byline' then e_byline(node)
    when 'caesura' then e_caesura(node)
    when 'cell' then e_cell(node)
    when 'div' then e_div(node)
    when 'docNumber' then e_doc_number(node)
    when 'form' then e_form(node)
    when 'g'    then e_g(node)
    when 'graphic' then e_graphic(node)
    when 'hi'   then e_hi(node)
    when 'head' then e_head(node)
    when 'item' then e_item(node)
    when 'juan' then e_juan(node)
    when 'l'    then e_l(node)
    when 'lb'   then e_lb(node)
    when 'lg'   then e_lg(node)
    when 'lem'  then e_lem(node)
    when 'list' then e_list(node)
    when 'milestone' then e_milestone(node)
    when 'note' then e_note(node)
    when 'p' then e_p(node)
    when 'row' then e_row(node)
    when 'seg' then e_seg(node)
    when 'table' then e_table(node)
    when 't'     then e_t(node)
    when 'unclear' then e_unclear(node)
    else
      traverse(node)
    end
  end

  def handle_text(node)
    s = node.text.chomp
    r = ''
    s.each_char do
      r << handle_char(it)
    end
    r
  end

  def init_juan
    @buf = ""
    @styles = Set.new(%w[default 標題])
  end

  def read_authority_catalog
    fn = File.join(
      Rails.configuration.x.authority, 
      'authority_catalog', 'json', "#{@canon}.json"
    )
    @works = JSON.parse(File.read(fn))
  end

  def read_mod_notes(doc)
    @mod_notes = Set.new

    doc.xpath("//note[@type='mod']").each do |e|
      n = e['n']
      @mod_notes << n

      # 例 T01n0026_p0506b07, 原註標為 7, CBETA 修訂為 7a, 7b
      n.match(/^(.*)[a-z]$/) { @mod_notes << $1 }
    end
  end

  def traverse(node)
    r = ""
    node.children.each do |c|
      s = handle_node(c)
      if node.name == "div" or node.name == "body"
        @buf << s
      else
        r << s
      end
    end
    r
  end

  def write_juan
    return if @juan < 1
    return if @buf.empty?

    @title = @works[@work]["title"]
    copyright = cbeta_copyright(@canon, @work, @juan, @publish, format: :docx)

    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <document>
        <settings>
          <title>#{@title}</title>
          <byline>#{@works[@work]["byline"]}</byline>
          <footer>第 {Page} 頁／共 {NumPages} 頁</footer>
          <styles>#{xml_styles}
          </styles>
        </settings>
        <body>
          <p rend="標題">#{@title}</p>
          #{@buf}#{copyright}</body>
      </document>
    XML
    init_juan

    dest = File.join(@dest_folder, "#{@v_work}_%03d.xml" % @juan)
    File.write(dest, xml)
  end

  def xml_styles
    r = ""
    indent = "\n      "

    @styles.each do |k|
      s = @predefined_styles[k]
      abort "[#{__LINE__}] style 未定義: #{k.inspect}" if s.nil?
      r << "#{indent}<style name=\"#{k}\">#{s}</style>"
    end

    r
  end

  include CbetaP5aShare
end
