# frozen_string_literal: true
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

    time_start = Time.now
    if args[:canon].nil?
      each_canon(@xml_root) do |c|
        next unless %w[T X].include?(c)
        @canon = c
        convert_canon(args)
      end
    else
      @canon = args[:canon]
      convert_canon(args)
    end
    puts "\n花費時間：" + ChronicDuration.output((Time.now - time_start).round(2))
  rescue => e
    puts "\n[#{__LINE__}] lb: #{@lb}"
    raise
  end

  def convert_canon(args)
    puts "\n[#{__LINE__}] canon: #{@canon}"
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
  
  def add_style(style)
    return if style == '各家會釋'
    return if style == '訂解總論'

    if @juan_styles.key?(@juan)
      @style_lb[style] = @lb
      @juan_styles[@juan] << style
    else
      abort "Error##{__LINE__}: @juan_styles 無 @juan: #{@juan.inspect}, style: #{style}, lb: #{@lb}"
    end
  rescue
    puts "[#{__LINE__}] style: #{style}"
    raise
  end

  def before_action(doc)
    p_note_lg(doc)
    p_tt_lb(doc)
    init_juan_styles(doc)
    read_lem_cf(doc)

    folder = Rails.root.join('data', 'xml4docx0', @canon, @vol)
    FileUtils.makedirs(folder)
    fn = File.join(folder, "#{@v_work}.xml")
    File.write(fn, doc.to_xml)
    @log.puts "#{__LINE__} #{@v_work} before_action 結束"
  end

  def before_parse(xml_file_path)
    xml = File.read(xml_file_path)

    # </cb:tt></p></cb:div><lb/>
    # => 
    # </cb:tt><lb/></p></cb:div>
    xml.gsub!(/<\/cb:tt>(<\/p>(?:<\/cb:div>)?\s*)(<lb [^>]+?\/>』?)/, '</cb:tt>\2\1')

    xml
  end

  def convert_vol(vol)
    @vol = vol
    src = File.join(@xml_root, @canon, vol)
    Dir.glob("*.xml", base: src, sort: true) do |f|
      convert_file(f)
    end
  end

  def copy_style(e, node, rend: nil)
    rends = []
    rends << rend unless rend.nil?

    if e["rend"]
      if e.key?('type') and e['type'] != 'dharani'
        abort "[#{__LINE__}] rend 與 type 同時存在, tag: #{e.name}, xml: #{e.to_xml}" 
      end

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
        if not %w[dharani interlinear xx 各家會釋 訂解總論].include?(e['type'])
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

    rends << 'entry_def' if e.parent.name == 'def'
    rends << 'p' if rends.include?('inlinenote') and e.name == 'p'

    unless rends.empty?
      r = rends.sort.join('_')
      node['rend'] = r
      add_style(r)
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

    @style_lb = {}
    xml = before_parse(src)
    doc = Nokogiri::XML(xml)
    doc.remove_namespaces!
    @source_desc = get_source_desc(doc)
    @title = get_title(doc)
    @log.puts "#{__LINE__} title: #{@title}"

    e = doc.at_xpath("//projectDesc/p[@lang='zh-Hant']")
    abort "找不到貢獻者" if e.nil?
    @contributors = e.text

    @in_corr = [false]
    before_action(doc)
    read_mod_notes(doc)

    @div_level = 0
    @list_level = 0
    @next_line_buf = +''
    @juan = 0
    @inline_note = [false]
    @in_lg = false
    @lg_type = [nil]
    @pre = [false]
    @seg = []
    xml = traverse(doc.root)
    write_juans(xml)
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
        case e.parent.name
        when 'div'
          return "<p>◎</p>"
        when 'list'
          return "<item><p>◎</p></item>" 
        else
          return '◎'
        end
      end
    end

    ''
  end

  def e_app(e, mode=nil)
    if mode=='text'
      lem = e.at('lem')
      return traverse(lem, mode)
    end
    
    r = +''
    if e['type'] == 'star'
      corresp = e['corresp'].delete_prefix('#')
      unless @notes.key?(corresp)
        corresp.sub!(/^(.*)[a-z]$/, '\1')
        abort "\n[#{__LINE__}] corresp #{corresp} 不存在" unless @notes.key?(corresp)
      end
      r << @notes[corresp]
    end
    r + traverse(e, mode)
  end
  
  def e_byline(e)
    # byline 在 item 裡，例: T52n2103_p0118c19
    if e.parent.name == 'item'
      return '　' + traverse(e)
    end

    add_style("byline")
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
    r = traverse(e)
    @div_level -= 1
    r
  end

  def e_doc_number(e)
    node = HTMLNode.new('p')
    node.content = traverse(e)
    node.to_s + "\n"
  end

  def e_foreign(e)
    return '' if e.key?('place') and e['place'].include?('foot')
    traverse(e)
  end

  def e_form(e)
    abort "form 的 parent 不是 entry" unless e.parent.name == 'entry'
    return '' if e.children.empty?
    
    add_style("entry_form")

    node = HTMLNode.new('p')
    node["rend"] = "entry_form"
    node.content = traverse(e)
    node.to_s + "\n"
  end

  # 2025-06-26 執行委員會 決議：
  #   * docx 不內嵌字型, 避免檔案太大。
  #   * Unicode 10 (含) 以內，直接使用 Unicode.
  #   * 有通用字, 使用通用字。
  def e_g(e, mode)
    id = e["ref"].delete_prefix("#")
    g = @gaiji[id]
    
    r = g['symbol']
    unless r.blank?
      if mode == 'tt'
        @t_buf[0] << r
        return ''
      else
        return r
      end
    end

    case id
    when /^CB/
      r = @gaiji.to_s(id)
      r = handle_char(r) if r.size == 1
    when /^(SD|RJ)/
      r = e_g_sidd(id, g, mode)
    else
      abort "未知的缺字類型: #{id}"
    end
    r
  end

  def e_g_sidd(id, g, mode)
    node = HTMLNode.new('font')
    node.content = g['char']
    node['rend'] = 'corr' if @in_corr.last

    if id.match?(/^SD/)
      node['name'] = "sidd"
      add_style("sidd")
    else
      node['name'] = "ranj"
      add_style("ranj")
    end

    if mode == 'tt'
      @t_buf[0] << node.to_s
      r = ''
    else
      r = node.to_s
    end

    # 如果有羅馬轉寫
    s = g['romanized']
    unless s.blank?
      if mode == 'tt'
        @t_buf[1] << "(#{s})"
      else
        r << "(#{s})"
      end
    end

    r
  end

  def e_graphic(e)
    url = e['url'].delete_prefix('../figures/')
    "<graphic url='#{url}'/>"
  end

  # node 可能在 app 下
  def get_parent_skip_app(e)
    nodes = e.ancestors
    while %w[app lem].include?(nodes.first.name)
      nodes.shift
    end
    nodes.first
  end

  def e_head(e)
    parent = get_parent_skip_app(e)
    case parent.name
    when 'div'
      if @div_level > 9
        return "<p>%s</p>" % traverse(e)
      end
  
      style = "標題 #{@div_level}"
      add_style(style)

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
    content = +''
    content << e['n'] if e.key?('n')
    content << traverse(e)
    return '' if content.empty?

    if @inline_note.last
      return content + '　'
    end
  
    node = HTMLNode.new('item')
    node.content = content
    r = +"\n"
    r << "  " * @list_level
    r << node.to_s
    r
  end

  def e_jhead(e)
    if e.parent.at_xpath('byline').nil?
      traverse(e)
    else
      add_style("juan")
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
      add_style("juan")
      node = HTMLNode.new('p')
      copy_style(e, node, rend: 'juan')
      node.content = content
      node.to_s + "\n"
    else
      content
    end
  end

  def e_l(e, mode)
    r = +''

    @log.puts "#{__LINE__} e_l, first_l: #{@first_l}, lg_type: #{@lg_type.last}, mode: #{mode}"
    if @first_l
      @first_l = false
    elsif mode != 'text'
      r << "<lb/>\n"
    end

    r << traverse(e)
    r
  end
  
  def lb_force_break?(e)
    return true if @pre.last
    return true if e['type'] == "honorific"
    false
  end

  def e_lb(e)
    return '' if e['ed'].start_with?('R')
    
    @lb = e['n']
    br = lb_force_break?(e)
    @log.puts "#{__LINE__} lb: #{@lb}, br: #{br}"

    r = +''
    r << "<lb/>\n" if br
    r << "<!-- lb: #{@lb} -->"    
    r
  end

  def can_use_seg_for_corr(lem)
    return false if @inline_note.last
    return false if lem.at_xpath('div | juan | list | p')
    true
  end

  def tt_traverse(e, mode, prefix, suffix)
    @log.puts "#{__LINE__} tt_traverse, prefi: #{prefix}, suffix: #{suffix}"
    @t_buf[0] << prefix
    @t_buf[1] << prefix
    traverse(e, mode)
    @t_buf[0] << suffix
    @t_buf[1] << suffix
  end

  def e_lem(e, mode)
    return traverse(e, mode) if @canon=='Y' or @canon=='TX'

    wit = e['wit']
    if (not wit.nil?) and wit.include? '【CB】' and not wit.include? @orig
      e_lem_corr(e, mode)
    else
      traverse(e, mode)
    end
  end

  def e_lem_corr(e, mode)
    add_style('corr')
    if can_use_seg_for_corr(e)
      if mode == 'tt'
        tt_traverse(e, mode, "<seg rend='corr'>", "</seg>")
        return ''
      else
        r = traverse(e, mode)
        r = "<seg rend='corr'>#{r}</seg>" unless r.empty?
        return  r
      end
    else
      @in_corr << true
      r = e_lem_font(e, mode)
      @in_corr.pop
      return r
    end
  end

  def e_lem_font(e, mode)
    if mode == 'tt'
      tt_traverse(e, mode, '<font rend="corr">', '</font>')
      return ''
    end

    r = traverse(e, mode)
    unless r.include?('corr')
      if r.include?('<graphic')
        # 避免 <font> 包 <graphic>
        r2 = r.dup
        r = +''
        r2.split(/(<graphic [^>]+>)/).each do
          if it.start_with?(/<graphic /)
            r << it
          elsif not it.empty?
            r << %(<font rend="corr">#{it}</font>) 
          end
        end
      elsif not r.empty?
        r = %(<font rend="corr">#{r}</font>)
      end
    end

    r
  end

  def e_lg(e)
    r = +''
    @lg_type << e['type']
    head = e.at_xpath('head')
    unless head.nil?
      node = HTMLNode.new('p')
      node['rend'] = 'head'
      add_style('head')
      node.content = traverse(head)
      r << node.to_s + "\n"
    end

    @in_lg = true
    @first_l = true
    
    node = HTMLNode.new('p')
    node['rend'] = e_lg_rends(e)
    add_style(node['rend'])

    node['style'] = e['style'] if e.key?('style')
    
    s = traverse(e)
    s.gsub!(/　+(<lb\/>)/, '\1')
    s.sub!(/　+$/, '')
    node.content = s

    @in_lg = false
    @lg_type.pop
    r << node.to_s + "\n"
    r
  end

  def e_lg_rends(e)
    rends = Set['lg']
    rends.merge(e['rend'].split) if e.key?('rend')

     # ex: X57n0980_p0779a14 <lg subtype="note1">
    if e.key?('subtype')
      a = e['subtype'].split
      a.delete_if { it =~ /^v\d$/ } # v4, v5, v7 不需特別樣式
      rends.merge(a)
    end

    if e.key?('place')
      a = e['place'].split
      a.delete('inline')
      rends.merge(a)
    end

    rends.to_a.sort.join('_')
  end

  def e_list(e)
    if @inline_note.last
      node = HTMLNode.new('p')
      node['rend'] = 'inlinenote_p'
      add_style('inlinenote_p')
      r = traverse(e).delete_suffix('　')
      node.content = "(#{r})"
      return node.to_s + "\n"
    end

    r = +''
    head = e.at_xpath('head')
    unless head.nil?
      node = HTMLNode.new('p')
      node['rend'] = 'head'
      add_style('head')
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
    r << node.to_s + "\n"
    r.gsub!(/<\/item><\/list>/, "</item>\n#{indent}</list>")
    r
  end

  def e_milestone(e)
    return "" unless e["unit"] == "juan"
    @juan = e["n"].to_i
    "<juan n='#{@juan}'/>"
  end

  # todo: Y26n0026_p0021a01
  def e_note(e, mode='xml')
    return '' if e['rend'] == 'hide'
    
    if e["place"] == "inline"
      return e_note_inline(e, mode)
    end
  
    r = case e["type"]
    when "add", "mod"
      e_note_add_mod(e, mode)
    when "orig"
      e_note_orig(e, mode)
    else
      ""
    end

    if mode == 'tt'
      @t_buf[0] << r
      r = ''
    end

    r
  end

  def e_note_add_mod(e, mode)
    s = traverse(e, 'text')

    n = e['n']
    if @lem_cf.key?(n)
      s << ' ' + @lem_cf[n]
    end

    r = "<footnote>#{s}</footnote>"
    r = "<p>#{r}</p>\n" if e.parent.name == 'div'
    r
  end

  def e_note_inline(e, mode)
    return "(#{traverse(e)})" if mode == 'text'

    if e.at_xpath('l')
      r = traverse(e, 'text')
      return "(%s)" % traverse(e, 'text')
    end

    if e.at_xpath('lg | list | p')
      e_note_text(e)
      @inline_note << true
      r = traverse(e)
      @log.puts "#{__LINE__} 夾注下有 (lg|list|p), xml: #{r}"
      @inline_note.pop
      return r
    end

    if @inline_note.last
      return "(%s)" % traverse(e)
    end

    @log.puts "#{__LINE__} seg inlinenote"
    @inline_note << true
    r = traverse(e)
    @inline_note.pop
    add_style("inlinenote")
    return %(<seg rend="inlinenote">(#{r})</seg>)
  end

  def e_note_orig(e, mode)
    n = e['n']
    return '' if @mod_notes.key?(n)

    s = traverse(e, 'text')
    r = "<footnote>#{s}</footnote>"
    @notes[n] = r

    r = "<p>#{r}</p>\n" if e.parent.name == 'div'
    r
  end

  # 如果 夾注 下已有 lg 或 list 或 p, 夾注下的文字就要包 p
  def e_note_text(e)
    e.children.each do |c|
      next unless c.text?
      next if c.text.gsub(/\s/, '').empty?
      p = c.add_previous_sibling("<p></p>").first
      p.add_child(c)
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

    r = traverse(e)
    @log.puts "#{__LINE__} #{r.inspect}"
    if e['type'] == 'pre'
      node.content = r
      @pre.pop
      e_p_pre(node)
      node.to_s + "\n"
    elsif r.match?(/<table rend=['"]table_tt['"]>/)
      r.sub!(/\A「(<table rend=['"]table_tt['"]>\s*<row>\s*<cell>)/m, '\1「')
      @log.puts "#{__LINE__} #{r.inspect}"
      r.gsub!(/<\/row>\s*<\/table>\s*<table rend=['"]table_tt['"]>\s*<row>/, '')
      @log.puts "#{__LINE__} #{r.inspect}"

      # 同一段落中，悉漢雙行對照 之後，可能還有別的東西，例： T18n0864Ap0196a14
      r.sub!(/\A(.*<\/table>)(.*)\z/m) do
        node.content = $2
        $1 + node.to_s + "\n"
      end
      @log.puts "#{__LINE__} #{r.inspect}"
      r
    else
      node.content = r
      node.to_s + "\n"
    end
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
    abort "[#{__LINE__}] rend 與 style 同時存在" if e.key?("rend") and e.key?("style")
    node = HTMLNode.new('seg')
    copy_style(e, node)
    node.content = traverse(e)
    node.to_s + "\n"
  end

  def e_sg(e)
    s = traverse(e)
    "(#{s})"
  end

  def e_t(e, mode)
    if e.has_attribute? 'place'
      return '' if e['place'].include? 'foot'
    end

    r = traverse(e, mode)

    tt = e.at_xpath('ancestor::tt')
    unless tt.nil?
      if %w(app single-line).include? tt['type']
        @log.puts "#{__LINE__} return t: #{r}"
        return r 
      end
      return r if tt['rend'] == 'normal'
    end

    if tt['place'] == 'inline'
      if e.key? 'style'
        s = e['style']
        if s =~ /^margin-left: ?(\d+)em$/
          i = $1.to_i
          r = '　' * i + r if i > 0
        else
          r = "<seg style='#{e['style']}'>#{r}</seg>"
        end
      end
      return r
    end

    # 處理雙行對照
    # <tt type="tr"> 也是 雙行對照
    if e['lang']=~/^sa/
      @t_buf = [+'', +''] 
      traverse(e, 'tt')
      @t_buf.join("<lb/>\n") + "<lb/>\n"
    else
      traverse(e, mode) + "<lb/>\n"
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

  def e_tt(e, mode)
    if e['place'] == 'inline' || e['rend'] == 'normal'
      || e['type'] == 'app' || e['type'] == 'single-line'
      return traverse(e, mode)
    end

    r = traverse(e, mode)
    r.sub!(/<lb\/>\n?\z/m, '')

    <<~XML
      <table rend='table_tt'>
        <row><cell>#{r}</cell>\n</row>
      </table>
    XML
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
    case code
    when 0x1F780..0x1F7FF, 0x20000..0x2A6DF, 0x2A700..0x2FFFF
      node['name'] = 'cbeta-supp'
      add_style("cbeta-supp")
      node.to_s
    when 0x30000..0x3134F
      # CJK Unified Ideographs Extension G 
      char
    when 0x31350..0x323AF
      # CJK Unified Ideographs Extension H
      char
    else
      abort "[#{__LINE__}] 未知 unicode: %X, lb: #{@lb}" % code
    end
  end

  def handle_node(node, mode)
    return "" if node.comment?
    return handle_text(node, mode) if node.text?
    return "" if PASS.include?(node.name)

    case node.name
    when 'anchor' then e_anchor(node)
    when 'app'    then e_app(node, mode)
    when 'byline' then e_byline(node)
    when 'caesura' then e_caesura(node)
    when 'cell' then e_cell(node)
    when 'div' then e_div(node)
    when 'docNumber' then e_doc_number(node)
    when 'foreign'   then e_foreign(node)
    when 'form' then e_form(node)
    when 'g'    then e_g(node, mode)
    when 'graphic' then e_graphic(node)
    when 'hi'   then e_hi(node)
    when 'head' then e_head(node)
    when 'item' then e_item(node)
    when 'jhead' then e_jhead(node)
    when 'juan' then e_juan(node, mode)
    when 'l'    then e_l(node, mode)
    when 'lb'   then e_lb(node)
    when 'lg'   then e_lg(node)
    when 'lem'  then e_lem(node, mode)
    when 'list' then e_list(node)
    when 'milestone' then e_milestone(node)
    when 'note' then e_note(node, mode)
    when 'p' then e_p(node)
    when 'row' then e_row(node)
    when 'seg' then e_seg(node)
    when 'sg'  then e_sg(node)
    when 't'     then e_t(node, mode)
    when 'table' then e_table(node)
    when 'trailer' then e_trailer(node)
    when 'tt' then e_tt(node, mode)
    when 'unclear' then e_unclear(node)
    else
      traverse(node, mode)
    end
  end

  def handle_text(node, mode)
    s = node.text.chomp
    return s if s =~ /\A\s*\z/

    r = +''
    s.each_char do
      r << handle_char(it)
    end

    r = "<p>#{r}</p>\n" if node.parent.name == 'div'
    r
  end

  def init_juan_styles(doc)
    @juan_styles = {}
    doc.root.xpath("//milestone[@unit='juan']").each do |ms|
      j = ms['n'].to_i
      @juan_styles[j] = Set.new(%w[default license 標題])
    end
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

    p = note.parent
    abort "error #{__LINE__}" unless p.name == 'p'
    @log.puts %(#{__LINE__} #{@v_work} <p id="#{p['id']}"> 下面有 <note place="inline"> 下面有 <lg id="#{lg['id']}">)

    new_p = nil
    p.children.each do |c|
      if c.text? or c.name == 'lb'
        new_p ||= add_p_before_p(p)
        @log.puts "#{__LINE__} 移動 #{log_node(c)}"
        new_p.add_child(c)
      elsif c.name=='note' and c['place']=='inline'
        if c.at_xpath('lg').nil?
          new_p ||= add_p_before_p(p)
          @log.puts "#{__LINE__} 移動 #{log_node(c)}"
          new_p.add_child(c)
        else
          new_p = nil
          p_note_lg_note(p, c)
        end
      else
        new_p ||= add_p_before_p(p)
        @log.puts "#{__LINE__} 移動 #{log_node(c)}"
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
        if new_p.nil?
          new_p = add_p_before_p(p, rend: 'inlinenote', style: note['style']) 
        end

        msg = +"#{@v_work} 移動 #{c.name}"
        if c.key?('type')
          msg << ", type: #{c['type']}"
        else
          msg << ": #{c.text[0,10]}..."
        end
        @log.puts "#{__LINE__} #{msg}"

        new_p.add_child(c)
      end
    end

    note.remove
    new_p
  end

  def add_p_before_p(p, rend: nil, style: nil)
    @log.puts "#{__LINE__} add_p_before_p, 在 <p id='#{p['id']}'> 前面新增一個 p"
    r = p.add_previous_sibling('<p></p>').first
    r['style'] = p['style'] if p.key?('style')
    r['style'] = style unless style.nil?

    rends = []
    rends.concat(p['rend'].split) if p.key?('rend')
    rends << rend unless rend.nil?
    r['rend'] = rends.join(' ') unless rends.empty?
    @log.puts "#{__LINE__} #{r.to_xml}"
    r
  end

  # T18n0859_p0178a08 tt 雙行對照
  # p 結束了，但第二行的 lb 在 p 外面
  # 把 lb 移到 p 裡面
  def p_tt_lb(doc)
    doc.root.xpath("//p/tt[last()]").each do |tt|
      next if %w(app single-line).include? tt['type']
      next if tt['rend'] == 'normal'
      next if tt['place'] == 'inline'
      next unless tt.next_element.nil?

      p = tt.parent
      while node = p.next_element
        break unless %w[lb pb].include?(node.name)
        p.add_child(node)
      end
    end
  end

  def read_authority_catalog
    fn = File.join(
      Rails.configuration.x.authority, 
      'authority_catalog', 'json', "#{@canon}.json"
    )
    @works = JSON.parse(File.read(fn))

    # 要放在 MS Word 摘要資訊裡的東西 使用 組字式
    repl = {
      "𡇪" => "[囗@告]",        # U+211EA
      "𬎞" => "[王*寶]",        # U+2C39E
      "𭖏" => "[峚-大+(企-止)]", # U+2D58F
      "𭮨" => "[辰*殳]",        # U+2DBA8
      "𮗿" => "[(工*刀)/言]"    # U+2E5FF
    }

    s = repl.keys.join()

    @works.each do |k, v|
      v['title'].gsub!(/[#{s}]/, repl) if v.key?('title')
      v['byline'].gsub!(/[#{s}]/, repl) if v.key?('byline')
    end
  end

  def read_lem_cf(doc)
    @lem_cf = {}

    doc.xpath("//lem").each do |lem|
      cf = ele_lem_cf(lem)
      next if cf.empty?

      app = lem.parent
      abort "error [#{__LINE__}]" unless app.name == 'app'
      @lem_cf[app['n']] = cf
    end
  end

  def read_mod_notes(doc)
    @mod_notes = {}
    @notes = {}
    doc.root.traverse do |e|
      case e.name
      when 'milestone'
        @juan = e['n'].to_i if e['unit'] == 'juan'
      when 'note'
        if e['type'] == 'mod'
          n = e['n']
          content = e_note(e)
          @mod_notes[n] = content
          @notes[n] = content

          # 例 T01n0026_p0506b07, 原註標為 7, CBETA 修訂為 7a, 7b
          if n =~ /^(.*)[a-z]$/
            n = $1
            @mod_notes[n] = content
            @notes[n] = content
          end
        end
      end
    end
  end

  def traverse(node, mode='xml')
    r = +""
    node.children.each do |c|
      r << handle_node(c, mode)
    end
    r
  end

  def write_juans(xml)
    buf = +''
    juan = nil
    xml.split(/(<juan n='.*?'\/>)/).each do |s|
      if s =~ /<juan n='(.*?)'\/>/
        j = $1
        write_juan(juan, buf)
        buf = +''
        juan = j.to_i
      else
        buf << s
      end
    end
    write_juan(juan, buf)
  end

  def write_juan(juan, buf)
    return if juan.nil?
    return if buf.empty?

    copyright = cbeta_copyright(@canon, @work, juan, @publish, format: :docx)

    buf.gsub!(/(?:<font name="sidd">[^<]+<\/font>)+/) do
      s = $&.gsub(/<[^>]+>/, '')
      %(<font name="sidd">#{s}<\/font>)
    end

    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <?xml-model href="../../../xml4docx.rng" type="application/xml" schematypens="http://relaxng.org/ns/structure/1.0"?>
      <document>
        <settings>
          <title>#{@works[@work]["title"]}</title>
          <byline>#{@works[@work]["byline"]}</byline>
          <footer>第 {Page} 頁／共 {NumPages} 頁</footer>
          <styles>#{xml_styles(juan)}
          </styles>
        </settings>
        <body>
          <p rend="標題">#{@title}</p>
          #{buf}#{copyright}</body>
      </document>
    XML

    dest = File.join(@dest_folder, "#{@v_work}_%03d.xml" % juan)
    File.write(dest, xml)
  end

  def xml_styles(juan)
    r = +""
    indent = "\n      "

    @juan_styles[juan].each do |k|
      s = @predefined_styles[k]
      abort "[#{__LINE__}] style 未定義: #{k.inspect}, lb: #{@style_lb[k]}" if s.nil?
      r << "#{indent}<style name=\"#{k}\">#{s}</style>"
    end

    r
  end

  def log_node(node)
    r = node.name
    if node.element?
      %w[id type n].each do |k|
        r << ", #{k}: #{node[k]}" if node.key?(k)
      end
    end
    s = node.text.gsub("\n", '').strip
    r << ", text: #{s[0,10]}..." unless s.empty?
    r
  end

  def error(msg)
    location = caller_locations.first
    file = File.basename(location.path)
    abort "\n#{file}:#{location.lineno}, lb: #{@lb}, #{msg}"
  end
  
  include CbetaP5aShare
end
