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
  
  def convert(args)
    @publish = args[:publish] || Date.today.strftime("%Y-%m")
    @pre_max = { work: '', text: '' }

    if args[:canon].nil?
      each_canon(@xml_root) do |c|
        args[:canon] = c
        convert_canon(args)
      end
    else
      convert_canon(args)
    end

    #puts "最長的 pre 內容是 #{@pre_max[:work]}: #{@pre_max[:text].size} 字"
    #puts @pre_max[:text]
  end

  def convert_canon(args)
    puts args[:canon]
    @canon = args[:canon]
    @orig = @cbeta.get_canon_symbol(@canon)
    @canon_name = @my_cbeta_share.get_canon_name(@canon)
    read_authority_catalog

    if args[:vol].nil?
      src = File.join(@xml_root, @canon)
      Dir.glob("*", base: src, sort: true) do |f|
        convert_vol(f)
      end
    else
      convert_vol(args[:vol])
    end
  end

  private

  def before_action(doc)
    p_note_lg(doc)
    folder = Rails.root.join('data', 'xml4docx0', @canon, @vol)
    FileUtils.makedirs(folder)
    fn = File.join(folder, "#{@v_work}.xml")
    File.write(fn, doc.to_xml)
    @log.puts "#{__LINE__} #{@v_work} before_action 結束"
  end

  def convert_vol(vol)
    puts "xml4docx1 #{vol}"
    @vol = vol
    src = File.join(@xml_root, @canon, vol)
    Dir.glob("*.xml", base: src, sort: true) do |f|
      convert_file(f)
    end
    puts
  end

  def copy_style(e, node, rend: nil)
    rends = []
    rends << rend unless rend.nil?

    if e["rend"]
      abort "rend 與 type 同時存在, tag: #{e.name}" if e['type']
      r = e['rend']
      
      case e.name
      when 'list'
        case r
        when 'no-marker'
          node['type'] = 'none'
          r = ''
        when 'ordered'
          node['type'] = 'ordered'
          r = ''
        else
          abort "unknown list rend: #{r}"
        end
      when 'table'
        rends << "table"
        rends << r
      else
        rends << r
      end
    end

    if e.key?("type")
      case e.name
      when 'list'
        node['type'] = e['type']
      else
        if not %w[dharani xx].include?(e['type'])
          rends << e['type']
        end
      end
    end
    
    if e["style"]
      r = CSSParser.new(e["style"]).to_class
      Rails.logger.info "style: #{e["style"]}, class: #{r}"
      if r.nil?
        node["style"] = e["style"] 
      else
        rends << r
      end
    end

    if @in_corr.last
      rends << 'corr'
      rends << 'p' if e.name == 'p'
    end

    rends << 'p' if rends.include?('inlinenote') and e.name == 'p'

    unless rends.empty?
      r = rends.sort.join('_')
      node['rend'] = r
      @styles << r
    end
  end

  def convert_file(fn)
    @v_work = File.basename(fn, '.xml')
    @v_work.sub!(/^(T\d\dn0220)(.*)$/, '\1')
    @work = CBETA.get_work_id_from_file_basename(@v_work)

    log_folder = Rails.root.join('log', 'xml4docx1', @canon, @vol)
    FileUtils.makedirs(log_folder)
    log_fn = File.join(log_folder, "#{@v_work}.log")
    @log = File.open(log_fn, 'w')
    
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

    @in_corr = [false]
    before_action(doc)
    init_juan
    read_mod_notes(doc)

    @div_level = 0
    @list_level = 0
    @next_line_buf = ''
    @juan = 0
    @inline_note = [false]
    @in_lg = false
    @pre = [false]
    @seg = []
    traverse(doc.root)
    write_juan
    @log.close
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

  def e_app(e, mode=nil)
    if mode=='text'
      lem = e.at('lem')
      return traverse(lem, mode)
    end
    
    r = ''
    if e['type'] == 'star'
      corresp = e['corresp'].delete_prefix('#')
      unless @mod_notes.key?(corresp)
        corresp.sub!(/^(.*)[a-z]$/, '\1')
        abort "\n[#{__LINE__}] corresp #{corresp} 不存在" unless @mod_notes.key?(corresp)
      end
      r << @mod_notes[corresp]
    end
    r + traverse(e)
  end
  
  def e_byline(e)
    # byline 在 item 裡，例: T52n2103_p0118c19
    if e.parent.name == 'item'
      return '　' + traverse(e)
    end

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
    case e.parent.name
    when 'div'
      if @div_level > 9
        return "<p>%s</p>" % traverse(e)
      end
  
      style = "標題 #{@div_level}"
      @styles << style
  
      node = HTMLNode.new('p')
      node["rend"] = style
      node.content = traverse(e)
      node.to_s + "\n"
    when 'lg'
      ''
    when 'list'
      if @inline_note.last
        traverse(e) + '　'
      else
        ''
      end
    else
      "<p>%s</p>" % traverse(e)
    end
  end

  def e_hi(e)
    node = HTMLNode.new('seg')
    copy_style(e, node)
    node.content = traverse(e)
    node.to_s + "\n"
  end

  def e_item(e)
    content = ''
    content << e['n'] if e.key?('n')
    content << traverse(e)
    return '' if content.empty?

    if @inline_note.last
      return content + '　'
    end
  
    node = HTMLNode.new('item')
    node.content = content
    r = "\n"
    r << "  " * @list_level
    r << node.to_s
    r
  end

  def e_jhead(e)
    if e.parent.at_xpath('byline').nil?
      traverse(e)
    else
      @styles << "juan"
      node = HTMLNode.new('p')
      node["rend"] = "juan"
      node.content = traverse(e)
      node.to_s + "\n"
    end
  end

  def e_juan(e, mode)
    content = traverse(e, mode)
    return content if mode == 'text'

    return '' if content.empty?

    if e.at_xpath('byline').nil?
      @styles << "juan"
      node = HTMLNode.new('p')
      copy_style(e, node, rend: 'juan')
      node.content = traverse(e)
      node.to_s + "\n"
    else
      traverse(e)
    end
  end

  def e_l(e, mode)
    r = ''
    
    if @first_l
      @first_l = false
    elsif mode != 'text'
      r << "<lb/>\n"
    end

    r << traverse(e)
    r
  end

  def e_lb(e)
    @lb = e['n']

    r = "<!-- lb: #{@lb} -->"
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

  def can_use_seg_for_corr(lem)
    return false if @inline_note.last
    return false if lem.at_xpath('juan | list | p')
    true
  end

  def e_lem(e)
    return traverse(e) if @canon=='Y' or @canon=='TX'

    wit = e['wit']
    if (not wit.nil?) and wit.include? '【CB】' and not wit.include? @orig
      if can_use_seg_for_corr(e)
        r = traverse(e)
        @styles << 'corr'
        r = "<seg rend='corr'>#{r}</seg>" unless r.empty?
        return  r
      else
        @in_corr << true
        r = traverse(e)
        r = %(<font rend="corr">#{r}</font>) unless r.include?('corr')
        @styles << 'corr'
        @in_corr.pop
        return r
      end
    else
      return traverse(e)
    end
  end

  def e_lg(e)
    r = ''
    head = e.at_xpath('head')
    unless head.nil?
      node = HTMLNode.new('p')
      node['rend'] = 'head'
      @styles << 'head'
      node.content = traverse(head)
      r << node.to_s + "\n"
    end

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
    r << node.to_s + "\n"
    r
  end

  def e_list(e)
    if @inline_note.last
      node = HTMLNode.new('p')
      node['rend'] = 'inlinenote_p'
      r = traverse(e).delete_suffix('　')
      node.content = "(#{r})"
      return node.to_s + "\n"
    end

    r = ''
    head = e.at_xpath('head')
    unless head.nil?
      node = HTMLNode.new('p')
      node['rend'] = 'head'
      node.content = traverse(head)
      r << node.to_s + "\n"
    end

    @list_level += 1
    node = HTMLNode.new('list')
    node['level'] = @list_level
    copy_style(e, node)
    node.content = traverse(e)
    @list_level -= 1
    indent = "  " * @list_level
    r << indent
    r << node.to_s + "\n"
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
  def e_note(e, mode='xml')
    return '' if e['rend'] == 'hide'
    
    if e["place"] == "inline"
      return "(#{traverse(e)})" if mode == 'text'
      if e.at_xpath('l')
        r = traverse(e, 'text')
        return "(%s)" % traverse(e, 'text')
      elsif e.at_xpath('lg | list | p')
        @inline_note << true
        r = traverse(e)
        @inline_note.pop
        return r
      elsif @inline_note.last
        return "(%s)" % traverse(e)
      else
        @inline_note << true
        r = traverse(e)
        @inline_note.pop
        @styles << "inlinenote"
        return %(<seg rend="inlinenote">(#{r})</seg>)
      end
    end
  
    case e["type"]
    when "add", "mod"
      "<footnote>%s</footnote>" % traverse(e, 'text')
    when "orig"
      n = e['n']
      return '' if @mod_notes.key?(n)
      s = traverse(e, 'text')
      @mod_notes[n] = s
      "<footnote>#{s}</footnote>"
    else
      ""
    end
  end

  def e_p(e)
    @pre << true if e['type'] == 'pre'

    node = HTMLNode.new('p')
    if @inline_note.last
      copy_style(e, node, rend: 'inlinenote')
    else
      copy_style(e, node)
    end

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

  def e_trailer(e)
    node = HTMLNode.new('p')
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

    node = HTMLNode.new('font')
    node.content = char
    node['rend'] = 'corr' if @in_corr.last
    if (0x20000..0x2A6DF).include?(code)
      node['name'] = 'hana_b'
      node.to_s
    elsif (0x2A700..0x2FFFF).include?(code)
      node['name'] = 'hana_c'
      node.to_s
    else
      abort "未知 unicode: %X, lb: #{@lb}" % code
    end
  end

  def handle_node(node, mode)
    return "" if node.comment?
    return handle_text(node) if node.text?
    return "" if PASS.include?(node.name)

    case node.name
    when 'anchor' then e_anchor(node)
    when 'app'    then e_app(node, mode)
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
    when 'jhead' then e_jhead(node)
    when 'juan' then e_juan(node, mode)
    when 'l'    then e_l(node, mode)
    when 'lb'   then e_lb(node)
    when 'lg'   then e_lg(node)
    when 'lem'  then e_lem(node)
    when 'list' then e_list(node)
    when 'milestone' then e_milestone(node)
    when 'note' then e_note(node, mode)
    when 'p' then e_p(node)
    when 'row' then e_row(node)
    when 'seg' then e_seg(node)
    when 't'     then e_t(node)
    when 'table' then e_table(node)
    when 'trailer' then e_trailer(node)
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

  # ex: T53n2122_p0683b03
  def p_note_lg(doc)
    doc.root.xpath("//p/note[@place='inline']/lg").each do
      p_note_lg_lg(it)
    end
  end

  def p_note_lg_lg(lg)
    note = lg.parent
    return unless note.name == 'note' # 同一個 note 下的 lg 可能被處理過了

    @log.puts "#{__LINE__} #{@v_work} p_note_lg_lg, id: #{lg['id']}"
    p = note.parent
    abort "error #{__LINE__}" unless p.name == 'p'

    new_p = nil
    p.children.each do |c|
      if c.text? or c.name == 'lb'
        new_p ||= add_p_before_p(p)
        new_p.add_child(c)
      elsif c.name=='note' and c['place']=='inline'
        new_p = nil
        p_note_lg_note(p, c)
      else
        new_p ||= add_p_before_p(p)
        new_p.add_child(c)
      end
    end
    p.remove
  end

  def p_note_lg_note(p, note)
    new_p = nil
    note.children.each do |c|
      if c.name=='lb' or (c.text? and c.text.gsub(/\s/, '').empty?)
        if new_p.nil?
          p.add_previous_sibling(c)
        else
          new_p.add_child(c)
        end
      elsif %w[lg p].include?(c.name)
        new_p = nil
        if c.key?('rend')
          c['rend'] = c['rend'] + ' inlinenote'
        else
          c['rend'] = 'inlinenote'
        end
        p.add_previous_sibling(c)
      else
        @log.puts "#{__LINE__} #{@v_work} 移動 #{c.name}"
        if new_p.nil?
          new_p = add_p_before_p(p, rend: 'inlinenote', style: note['style']) 
        end
        new_p.add_child(c)
      end
    end
    note.remove
  end

  def add_p_before_p(p, rend: nil, style: nil)
    @log.puts "add_p_before_p, work: #{@v_work}, p id: #{p['id']}"
    r = p.add_previous_sibling('<p></p>').first
    r['style'] = p['style'] if p.key?('style')
    r['style'] = style unless style.nil?

    rends = []
    rends.concat(p['rend'].split) if p.key?('rend')
    rends << rend unless rend.nil?
    r['rend'] = rends.join(' ') unless rends.empty?
    @log.puts r.to_xml
    r
  end

  def read_authority_catalog
    fn = File.join(
      Rails.configuration.x.authority, 
      'authority_catalog', 'json', "#{@canon}.json"
    )
    @works = JSON.parse(File.read(fn))
  end

  def read_mod_notes(doc)
    @mod_notes = {}

    doc.xpath("//note[@type='mod']").each do |e|
      n = e['n']
      content = e_note(e)
      @mod_notes[n] = content

      # 例 T01n0026_p0506b07, 原註標為 7, CBETA 修訂為 7a, 7b
      if n =~ /^(.*)[a-z]$/
        n = $1
        @mod_notes[n] = content
      end
    end
  end

  def traverse(node, mode='xml')
    r = ""
    node.children.each do |c|
      s = handle_node(c, mode)
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
      <?xml-model href="../../../xml4docx.rng" type="application/xml" schematypens="http://relaxng.org/ns/structure/1.0"?>
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
