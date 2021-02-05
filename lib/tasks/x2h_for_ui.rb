require 'cgi'
require 'date'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'set'
require 'cbeta'
require_relative 'html-node'
require_relative 'x2h_share'
require_relative 'cbeta_p5a_share'
require_relative 'share'

# Convert CBETA XML P5a to HTML for UI
#
# 只產生 CBETA版
#
# CBETA XML P5a 可由此取得: https://github.com/cbeta-git/xml-p5a
#
# 轉檔規則請參考: http://wiki.ddbc.edu.tw/pages/CBETA_XML_P5a_轉_HTML
class P5aToHTMLForUI
  # 內容不輸出的元素
  PASS=['back', 'figDesc', 'teiHeader']
  
  # 某版用字缺的符號
  MISSING = '－'
  
  private_constant :PASS, :MISSING

  # @param xml_root [String] 來源 CBETA XML P5a 路徑
  # @param out_root [String] 輸出 HTML 路徑
  def initialize(publish, xml_root, out_root)
    @publish_date = publish
    @xml_root = xml_root
    @out_root = out_root
    @cbeta = CBETA.new
    @gaijis = MyCbetaShare.get_cbeta_gaiji
    @gaijis_skt = MyCbetaShare.get_cbeta_gaiji_skt
    @canon_names = read_canon_name

    fn = Rails.root.join('data-static', 'facsimile', 'JM.json')
    s = File.read(fn)
    @jm_facsimile = JSON.parse(s)
    @j_facs_juans = Set.new
    @j_pages = 0
    @us = UnicodeService.new
  end

  # 將 CBETA XML P5a 轉為 HTML
  #
  # @example for convert 大正藏全部:
  #
  #   x2h = CBETA::P5aToHTML.new('/PATH/TO/CBETA/XML/P5a', '/OUTPUT/FOLDER')
  #   x2h.convert('T')
  #
  # T 是大正藏的 ID, CBETA 的藏經 ID 系統請參考: http://www.cbeta.org/format/id.php
  def convert(target=nil)
    
    if target.nil?
      convert_all
    else
      if target.size.between?(1,2)
        arg = target.upcase
        convert_canon(arg)
      else
        puts "注意：因為某些典籍單卷跨冊，轉檔必須以某部藏經為單位，例如參數 T 表示轉換整個大正藏。"
        work_id = CBETA.get_work_id_from_file_basename(target)
        @canon = CBETA.get_canon_id_from_work_id(work_id)
        convert_canon_init(@canon)
        @vol = target.sub(/^(#{@canon}\d+).*$/, '\1')
        fn = File.join(@xml_root, @canon, @vol, "#{target}.xml")
        convert_sutra(fn)
      end
    end

    stat_jm_facs
  end

  private
  
  include CbetaShare
  
  # 取得 app 下的修訂依據
  def app_note_cf(app)
    # ex: T32n1670A.xml, p. 703a16
    # <note type="cf1">K30n1002_p0257a01-a23</note>
    refs = []
    app.xpath('descendant::note').each do |n|
      if n.key?('type') and n['type'].start_with? 'cf'
        s = n.content
        refs << s
      end
    end
    if refs.empty?
      ''
    else
      '修訂依據：' + refs.join('、') + '。'
    end
  end
  
  def app_readings(app)
    readings = []
    lem = ''
    app.xpath('lem|rdg').each do |e|
      s = traverse(e, 'footnote')
      s = MyCbetaShare.remove_puncs(s)
      lem = s if e.name == 'lem'
      w = e['wit']
      readings.each do |r|
        if s == r[:text]
          r[:wit] += w
          s = nil
          break
        end
      end
      next if s.nil?
      readings << { wit: w, text: s}
    end
    return lem, readings
  end
  
  def before_parse_xml(xml_fn)
    @back = { 0 => '' }
    @back_orig = { 0 => '' }
    @char_count = 1
    @dila_note = 0
    @div_count = 0
    @gaiji_norm = [true]
    @juan = 0
    @lg_row_open = false
    @mod_notes = Set.new
    @next_line_buf = ''
    @notes_mod = {}
    @notes_orig = {}
    @notes_add = {}
    @open_divs = []
    @sutra_no = File.basename(xml_fn, ".xml")
    $stderr.print "\nx2h_for_ui #{@sutra_no}"
    @work_id = CBETA.get_work_id_from_file_basename(@sutra_no)
    @updated_at = MyCbetaShare.get_update_date(xml_fn)
  end

  def convert_all
    Dir.entries(@xml_root).sort.each do |c|
      next unless c.match(/^#{CBETA::CANON}$/)
      convert_canon(c)
    end
  end
  
  def convert_canon(c)
    convert_canon_init(c)
    $stderr.puts 'convert canon: ' + c
    folder = File.join(@xml_root, @canon)
    
    FileUtils::rm_rf @out_folder
    FileUtils::mkdir_p @out_folder
    
    Dir.entries(folder).sort.each do |vol|
      next if vol.start_with? '.'
      convert_vol(vol)
    end
  end

  def convert_canon_init(c)
    @canon = c
    @out_folder = File.join(@out_root, @canon)
    @html_buf = {}
    @back_buf = {}

    @orig = @cbeta.get_canon_symbol(c)
    abort "未處理底本" if @orig.nil?

    @canon_name = @canon_names[c]
    @orig_short = @orig.sub(/^【(.*)】$/, '\1')
  end
  
  def convert_sutra(xml_fn)
    before_parse_xml(xml_fn)

    text = parse_xml(xml_fn)
    
    folder = File.join(@out_folder, @work_id)
    FileUtils.makedirs folder
    
    # 註標移到 lg-cell 裡面，不然以 table 呈現 lg 會有問題
    text.gsub!(/(<a class='noteAnchor'[^>]*><\/a>)(<div class="lg-cell"[^>]*>)/, '\2\1')
    
    juans = text.split(/(<juan \d+>)/)
    juan_no = nil
    buf = ''
    # 一卷一檔
    juans.each { |j|
      if j =~ /<juan (\d+)>$/
        juan_no = $1.to_i
      elsif juan_no.nil?
        buf = j
      else
        write_juan(folder, juan_no, buf+j)
        buf = ''
      end
    }
  end
  
  def convert_vol(vol)
    @vol = vol
    
    source = File.join(@xml_root, @canon, vol)
    Dir.entries(source).sort.each do |f|
      next if f.start_with? '.'
      fn = File.join(source, f)
      convert_sutra(fn)
    end
  end
  
  def e_anchor(e, mode)
    return '' if mode=='footnote'
    id = e['id']
    if e.has_attribute?('id')
      if id.start_with?('nkr_note_orig')
        note = @notes[id]
        note_text = traverse(note)
        n = id[/^nkr_note_orig_(.*)$/, 1]
        @back[@juan] += "<span class='footnote' id='n#{n}'>#{note_text}</span>\n"
        return "<a class='noteAnchor' href='#n#{n}'></a>"
      elsif id.start_with? 'fx'
        return "<span class='star'>[＊]</span>"
      end
    end

    if e.has_attribute?('type')
      if e['type'] == 'circle'
        return '◎'
      end
    end

    ''
  end

  def e_app(e, mode)
    if mode=='footnote'
      lem = e.at('lem')
      return traverse(lem, mode)
    end
    
    r = ''
    if e['type'] == 'star'
      c = e['corresp'][1..-1]
      r = "<a class='noteAnchor star' href='#n#{c}'></a>"
    elsif e.key? 'n'
      # 先不自動產生 app table, 等 cbeta 修改 <note type="mod">
      #@app_n = e['n']
      #lem, readings = app_readings(e)
      #note = readings_to_note(readings)
      #note += app_note_cf(e)
      #if @notes_mod[@juan].key? @app_n
      #  @notes_mod[@juan][@app_n] += note
      #end
    end
    r + traverse(e)
  end

  def e_byline(e, mode)
    return traverse(e, mode) if mode=='footnote'
    node = HtmlNode.new('p')
    classes = ['byline']
    classes << e['rend'] if e.key? 'rend'
    node['class'] = classes.join(' ')
    node.content = line_info + traverse(e, mode)
    node.to_s + "\n"
  end

  def e_caesura(e, mode)
    if @lg_type == 'regular'
      return e.to_s
    else
      if e.key?('style')
        e['style'].match(/text-indent:(\d+)em/) do
          return '　' * ($1.to_i)
        end
      else
        return '　　'
      end
    end
    ''
  end

  def e_cell(e)
    cell = HtmlNode.new('div')
    cell['class'] = 'bip-table-cell'
    cell['rowspan'] = e['rows'] if e.key? 'rows'
    cell['colspan'] = e['cols'] if e.key? 'cols'
    cell['style']   = e['style'] if e.key? 'style'
    cell.content = traverse(e)
    cell.to_s
  end

  def e_corr(e, mode)
    return traverse(e, mode) if mode=='footnote'
    r = ''
    #if e.parent.name == 'choice'
    #  sic = e.parent.at_xpath('sic')
    #  unless sic.nil?
    #    n = @notes_dila[@juan].size + 1
    #    r = "<a class='noteAnchor dila' href='#dila_note#{n}'></a>"
    #
    #    note = @orig
    #    sic_text = traverse(sic, 'footnote')
    #    if sic_text.empty?
    #      note += MISSING
    #    else
    #      note += sic_text
    #    end
    #    @notes_dila[@juan] << "<span class='footnote dila' id='dila_note#{n}'>#{note}</span>"
    #  end
    #end
    r + "<span class='cbeta'>%s</span>" % traverse(e)
  end

  def e_div(e, mode)
    return traverse(e, mode) if mode=='footnote'
    @div_count += 1
    n = @div_count
    if e.has_attribute? 'type' or e.key? 'rend'
      return e_div_node(e)
    else
      return traverse(e)
    end
  end

  def e_div_node(e)
    @open_divs << e
    r = traverse(e)
    @open_divs.pop

    node = HtmlNode.new('div')
    node.content = r

    classes = []

    if e.key? 'type'
      classes << "div-#{e['type']}"
    end

    if e.key? 'rend'
      classes << e['rend']
    end

    unless classes.empty?
      node['class'] = classes.join(' ')
    end

    node.to_s
  end

  def e_foreign(e, mode)
    return '' if e.key?('place') and e['place'].include?('foot')
    html_span(e, mode)
  end

  def e_g(e, mode)
    gid = e['ref'][1..-1]
    
    if gid.start_with? 'CB'
      g = @gaijis[gid]
    else
      g = @gaijis_skt[gid]
    end
    
    abort "Line:#{__LINE__} 無缺字資料:#{gid}" if g.nil?
    zzs = g['composition']
    
    if mode == 'txt'
      return g['romanized'] if gid.start_with?('SD')
      if zzs.nil?
        abort "缺組字式：#{g}"
      else
        return zzs
      end
    end

    @char_count += 1

    if gid.start_with?('SD')
      return g['symbol'] if g.key? 'symbol'
      return "<span class='siddam' roman='#{g['romanized']}' code='#{gid}' char='#{g['char']}'/>"
    end
    
    if gid.start_with?('RJ')
      return "<span class='ranja' roman='#{g['romanized']}' code='#{gid}' char='#{g['char']}'/>"
    end
   
    default = ''
    span = HtmlNode.new('span')
    if g.key?('unicode') and (not g['unicode'].empty?)
      span['unicode'] = g['unicode']
      if @us.level1?(g['unicode'])
        return g['uni_char']
      elsif @us.level2?(g['unicode'])
        default = g['uni_char']
      end
    end

    nor = ''
    # 註解常有用字差異，不用通用字，否則會變成兩個版本的用字一樣
    # 例：T02n0099, 181b08, 註：㝹【CB】，[少/免]【大】
    unless mode.include? 'footnote'
      if @gaiji_norm.last # 如果 沒有特別說 不能用 通用字
        if @us.level2?(g['norm_unicode'])
          nor = g['norm_uni_char']
          default = nor if default.empty?
        end

        c = g['norm_big5_char']
        unless c.nil? or c.empty?
          nor += ', ' unless nor==''
          nor += c
          default = c if default.empty?
        end
      end
    end

    if default.empty?
      abort "缺組字式：#{gid}" if zzs.blank?
      default = zzs
    end
    
    #href = 'http://www.cbeta.org/dict_word/gaiji-cb/%s/%s.gif' % [gid[2, 2], gid]
    href = 'https://raw.githubusercontent.com/cbeta-org/gaiji-CB/master/%s/%s.gif'
    href = href % [gid[2, 2], gid]
    
    span['id'] = gid
    span['class'] = 'gaijiInfo'
    span['figure_url'] = href
    span['zzs'] = zzs
    span.content = default
    
    unless @back[@juan].include?(href)
      @back[@juan] += span.to_s + "\n"
    end
    unless @back_orig[@juan].include?(href)
      @back_orig[@juan] += span.to_s + "\n"
    end
    "<a class='gaijiAnchor' href='##{gid}'>#{default}</a>"
  end

  def e_graphic(e)
    a = e['url'].split('/')
    abort "\n#{__LINE__} url: #{url}" if a.size < 2
    url = File.join(Rails.configuration.x.figure_url, a[-2], a[-1])
    %(<img src="#{url}" class="graphic" />)
  end

  def e_head(e, mode)
    return traverse(e, mode) if mode=='footnote'
    return '' if e['type'] == 'added'

    node = HtmlNode.new('p')
    node.content = traverse(e, mode)

    classes = []
    case e.parent.name
    when 'div'
      node['data-head-level'] = @open_divs.size
      classes << 'head'
    when 'lg'
      classes << 'lg-head'
    else
      classes << 'head'
    end

    if e.key?('rend')
      classes << e['rend']
    end

    node['class'] = classes.join(' ')

    node.to_s
  end

  def e_item(e, mode)
    s = traverse(e, mode)
    li = HtmlNode.new('li')
    
    # ex: T18n0850_p0087a14
    if e.key? 'n'
      n = e['n']
      i = n.size
      s = n + s
      li['style'] = "margin-left:#{i}em;text-indent:-#{i}em"
    end
    
    return s if mode=='footnote'

    a = e.xpath('ancestor::list')
    li.content = line_space(a.size * 2)
    li.content += s

    li.to_s + "\n"
  end

  def e_juan(e, mode)
    return traverse(e, mode) if mode=='footnote'
    "<p class='juan'>%s</p>" % traverse(e)
  end

  def e_l(e, mode)
    return traverse(e, mode) if mode=='footnote'

    row = HtmlNode.new('div')
    #row = Nokogiri::XML("<div></div>").root
    row['class'] = 'lg-row'

    content = traverse(e)
    if @lg_type == 'regular'
      row.content = e_l_regular_cells(content, e)
    else
      row.content = "<div class='lg-cell'>#{content}</div>\n"
    end
    #row.add_child(html)

    spaces = ''
    if e.key?('style')
      if @lg_type == 'regular'
        s = remove_text_indent_from_style(e['style'])
        row['style'] = s unless s.empty?
      else
        row['style'] = e['style']
      end
    elsif @first_l and @lg_type != 'regular'
      # lg 的 text-indent 要放到第一個 cell
      parent = e.parent()
      if parent.has_attribute?('style')
        parent['style'].match(/text-indent: ?(-?\d+)em/) do |m|
          row['style'] = m[0]
          spaces = line_space(m[1].to_i)
        end
      end
    end
    @first_l = false

    #row.to_xml(encoding: 'UTF-8') + "\n"
    spaces + row.to_s
  end

  def e_l_regular_cells(s, e)
    indent = nil
    spaces = nil
    if e.key?('style')
      e['style'].match(/text-indent: ?(-?\d+)em/) do |m|
        indent = $&
        spaces = line_space($1)
      end
    end

    # 如果第一個 <l> 未指定 text-indent, 就由 lg 繼承
    if indent.nil? and @first_l
      lg = e.parent
      if lg.key?('style')
        lg['style'].match(/text-indent: ?(-?\d+)em/) do |m|
          indent = $&
          spaces = line_space($1)
        end
      end
    end

    a = s.split(/(<caesura[^>]*?\/>)/)
    r = ''
    a.each_with_index do |v, i|
      next if v.start_with?('<caesura')
      
      if i == 0
        if indent.nil?
          r += "<div class='lg-cell'>#{v}</div>\n"
        else
          r += "#{spaces}<div class='lg-cell' style='#{indent}'>#{v}</div>\n"
        end
        next
      end

      caesura = a[i-1]
      if caesura.match(/<caesura ([^>]*?)\/>/)
        style = $1
        if caesura.match(/text\-indent: ?(\-?\d+)em/)
          s = line_space($1)
        else
          s = ''
        end
        r += "#{s}<div class='lg-cell' #{style}>#{v}</div>\n"
      else
        r += "<div class='lg-cell'>#{v}</div>\n"
      end
    end
    r
  end

  def e_lb(e, mode)
    return '' if mode=='footnote'
    return '' if e['type']=='old'
    return '' if e['ed'] != @canon
    
    @lb_r = nil
    # 卍續藏有 X 跟 R 兩種 lb
    if @canon=='X'
      lbr = e.next
      unless lbr.nil?
        if lbr.name == 'lb' and lbr['ed'].start_with? 'R'
          n = lbr['n']
          @lb_r = lbr['ed'] + '.' + n[0, 4] + '.' + n[-3..-1]
        end
      end
    end

    @char_count = 1
    @lb = e['n']
    line_head = CBETA.get_linehead(@sutra_no, e['n'])
    r = ''

    node = HtmlNode.new('span')
    node['class'] = 'lb'
    node['class'] += ' honorific' if e['type'] == 'honorific'
    node['id'] = line_head
    node['data-lr'] = @lb_r unless @lb_r.nil?
    node.content = line_head
    r += node.to_s

    case e['ed']
    when 'GA', 'GB'
      v = @vol[2..-1]
      if @lb.end_with? 'a01'
        n = @lb[0, 4]
        r += %(<a class="facsimile" data-ref="#{e['ed']}v#{v}p#{n}"></a>)
      end
    when 'J'
      h = @jm_facsimile[@sutra_no]
      unless h.nil?
        if h.key? @lb
          r += %(<a class="facsimile" data-ref="#{h[@lb]}"></a>)
          @j_facs_juans << "#{@work_id}_#{@juan}"
        end
      end
    when 'T'
      v = @vol[1..-1]
      if @first_lb_in_juan or @lb.end_with?('a01')
        n = @lb[0, 4]
        r += %(<a class="facsimile" data-ref="Tv#{v}p#{n}"></a>)
        @first_lb_in_juan = false
      end
    end
    
    r += e_lb_p(e)

    unless @next_line_buf.empty?
      r += @next_line_buf
      @next_line_buf = ''
    end

    @first_l_in_line = true

    r
  end

  def e_lb_p(e)
    r = ''
    p = e.at_xpath('ancestor::p')
    return '' if p.nil?
    return '' unless p.key? 'style'
    i = 0
    p['style'].match(/margin-left:(\d+)em/) do |m|
      i += m[1].to_i
    end
    line_space(i)
  end

  def e_lem(e)
    app = e.parent
    if app.key?('n')
      n = app['n']
      if @notes_mod[@juan].key?(n)
        @notes_mod[@juan][n] += e_lem_cf(e)
      end
    end

    content = traverse(e)
    wit = e['wit']
    if wit.include? '【CB】' and not wit.include? @orig
      return "<span class='cbeta'>%s</span>" % content
    else
      return content
    end
  end

  def e_lem_cf(e)
    cfs = []
    e.xpath('note').each do |c|
      next unless c.key?('type')
      next unless c['type'].match(/^cf\d+$/)
      s = traverse(c, 'footnote')
      if s.match(/^T\d{2,3}n.{5}p[a-z\d]\d{3}[a-z]\d\d$/)
        s = "<span class='cbeta-linehead'>#{s}</span>"
      end
      cfs << s
    end

    return '' if cfs.empty?

    s = cfs.join('; ')
    "(cf. #{s})"
  end

  def e_list(e, mode)
    s = traverse(e, mode)
    return s if mode=='footnote'
    
    ul = HtmlNode.new('ul')

    ul['class'] = e['rend'] if e.key? 'rend'
    
    # ex: T18n0850_p0087a14
    item = e.at_xpath('descendant::item') # item 可能在 app 裡
    if item.key? 'n'
      ul['style'] = "list-style-type:none;margin-left:0;padding-left:0"
    end
    
    ul.content = s
    ul.to_s
  end

  def e_milestone(e)
    r = ''
    if e['unit'] == 'juan'
      r += "</div>" * @open_divs.size  # 如果有 div 跨卷，要先結束, ex: T55n2154, p. 680a29, 跨 19, 20 兩卷
      @juan = e['n'].to_i
      @back[@juan] = @back[0]
      @back_orig[@juan] = @back_orig[0]
      @first_lb_in_juan = true
      @notes_mod[@juan] = {}
      @notes_orig[@juan] = {}
      @notes_add[@juan] = []
      r += "<juan #{@juan}>"
      @open_divs.each { |d|
        r += "<div class='div-#{d['type']}'>"
      }
      print " #{@juan}"
    end
    r
  end

  def e_mulu(e, mode)
    return traverse(e, mode) if mode=='footnote'
    r = ''
    if e['type'] == '品'
      @pass << false
      r = "<mulu class='pin' s='%s'/>" % traverse(e, 'txt')
      @pass.pop
    end
    r
  end
  

  def e_note(e, mode)
    return e_note_foot(e) if mode == 'footnote'
      
    n = e['n']
    if e.has_attribute?('type')
      t = e['type']
      case t
      when 'add'
        n = @notes_add[@juan].size + 1
        n = "cb_note_#{n}"
        s = traverse(e, 'footnote')
        s += e_note_add_cf(e)
        @notes_add[@juan] << "<span class='footnote add' id='#{n}'>#{s}</span>"
        return "<a class='noteAnchor add' href='##{n}'></a>"
      when 'equivalent', 'rest' then return ''
      when 'orig'       then return e_note_orig(e)
      when 'mod'
        @notes_mod[@juan][n] = traverse(e, 'footnote')
        return "<a class='noteAnchor' href='#n#{n}'></a>"
      when 'star'
        href = 'n' + e['corresp'].sub(/^#(.*)$/, '\1')
        return "<a class='noteAnchor star' href='##{href}'></a>"
      else
        return '' if t.start_with?('cf')
      end
    end

    if e.has_attribute?('resp')
      return '' if e['resp'].start_with? 'CBETA'
    end

    if e.has_attribute?('place')
      r = traverse(e)
      
      c = case e['place']
      when 'interlinear' then 'interlinear-note'
      when 'inline', 'inline2' then 'doube-line-note'
      end
      
      return "<span class='#{c}'>#{r}</span>"
    else
      return traverse(e)
    end
  end

  def e_note_add_cf(e)
    n = e['n']
    return '' if n.nil?

    app = e.next_sibling
    return '' if app.nil?
    return '' unless app.name == 'app'
    return '' unless app['n'] == n

    lem = app.at_xpath('lem')
    return '' if lem.nil?
    e_lem_cf(lem)
  end
  
  def e_note_foot(e)
    return '' unless e.key?('place')
    if %w(interlinear inline).include? e['place']
      return '(%s)' % traverse(e, 'footnote')
    else
      return ''
    end
  end


  def e_note_orig(e)
    n = e['n']
    subtype = e['subtype']
    s = traverse(e, 'footnote')
    @notes_orig[@juan][n] = s
    @notes_mod[@juan][n] = s
    
    #c = @canon
    
    # 如果 CBETA 沒有修訂，就跟底本的註一樣
    # 但是 CBETA 修訂後的編號，有時會加上 a, b
    # T01n0026, p. 506b07, 大正藏校勘 0506007, CBETA 拆為 0506007a, 0506007b
    #c += " cb" unless @mod_notes.include?(n) or @mod_notes.include?(n+'a')

    label = case subtype
    when 'biao' then " data-label='標#{n[-2..-1]}'"
    when 'jie'  then " data-label='解#{n[-2..-1]}'"
    when 'ke'   then " data-label='科#{n[-2..-1]}'"
    else ''
    end
    
    if @mod_notes.include?(n)
      return ''
    else
      #return "<a class='noteAnchor #{c}' href='#n#{n}'#{label}></a>"
      return "<a class='noteAnchor' href='#n#{n}'#{label}></a>"
    end
  end
  
  def e_p(e, mode)
    return traverse(e, mode) if mode=='footnote'
    
    classes = []
    if e.at_xpath('figure')
      node = HtmlNode.new('div')
      classes << 'div-figure'
    else
      node = HtmlNode.new('p')
    end

    classes << e['type'] if e.key? 'type'

    # p 的 rend 屬性可能有空格隔開的多值
    classes += e['rend'].split if e.key? 'rend'
    node['class'] = classes.join(' ') unless classes.empty?

    node.content = line_info

    if e.key? 'style'
      node['style'] = e['style'] 
      e['style'].match(/text-indent:(\d+)em/) do |m|
        node.content += line_space(m[1].to_i)
      end
    end
    
    node.content += traverse(e)
    node.to_s + "\n"
  end

  def e_pb(e, mode)
    if e['ed'] == 'J'
      @j_pages += 1
    end
    ''
  end

  def e_rdg(e)
    ''
  end

  def e_ref(e)
    node = HtmlNode.new('span')
    node.content = traverse(e)
    node['style'] = e['style'] if e.key? 'style'

    if e.key? 'cRef'
      t = e['cRef']
      if t.start_with? 'PTS'
        node['class'] = 'hint'
        node['data-text'] = t
        n = t.split('.').last
        node['data-label'] = "P.#{n}"
      end
    end
    node.to_s
  end
  
  def e_reg(e)
    r = ''
    choice = e.at_xpath('ancestor::choice')
    r = traverse(e) if choice.nil?
    r
  end
  
  def e_row(e)
    "<div class='bip-table-row'>" + traverse(e) + "</div>"
  end

  def e_sg(e, mode)
    '(' + traverse(e, mode) + ')'
  end
  
  def e_sic(e, mode)
    ''
  end

  def e_t(e, mode)
    if e.has_attribute? 'place'
      return '' if e['place'].include? 'foot'
    end
    r = traverse(e, mode)
    return r if mode=='footnote'

    tt = e.at_xpath('ancestor::tt')
    unless tt.nil?
      return r if %w(app single-line).include? tt['type']
      return r if tt['rend'] == 'normal'
    end

    if e.key? 'style'
      r = "<span style='#{e['style']}'>#{r}</span>"
    end

    return r if tt['place'] == 'inline'

    # 處理雙行對照
    # <tt type="tr"> 也是 雙行對照
    i = e.xpath('../t').index(e)
    case i
    when 0
      return r + '　'
    when 1
      @next_line_buf += r + '　'
      return ''
    else
      return r
    end
  end

  def e_tt(e, mode)
    traverse(e, mode)
  end

  def e_table(e)
    node = HtmlNode.new('div')
    node.content = traverse(e)

    classes = ['bip-table']
    classes << e['rend'] if e.key? 'rend'
    node['class'] = classes.join(' ')

    if e.key? 'style'
      node['style'] = e['style']
    end

    node.to_s
  end

  def e_term(e, mode)
    norm = true
    if e['behaviour'] == "no-norm"
      norm = false
    end
    @gaiji_norm.push norm
    r = traverse(e)
    @gaiji_norm.pop
    r
  end

  def e_text(e)
    norm = true
    if e['behaviour'] == "no-norm"
      norm = false
    end
    @gaiji_norm.push norm
    r = traverse(e)
    @gaiji_norm.pop
    r
  end
  
  def e_unclear(e)
    ele_unclear(e) do |s|
      %(<span class="unclear" data-cert="#{e['cert']}">#{s}</span>)
    end
  end
  
  def filter_html(html, ed)
    frag = Nokogiri::HTML.fragment(html)
    frag.search("r").each do |node|
      if node['w'].include? ed
        html_only_this_edition = filter_html(node.inner_html, ed)
        node.add_previous_sibling html_only_this_edition
      end
      node.remove
    end
    frag.to_html
  end
  
  def get_editions(doc)
    r = Set.new [@orig, "【CBETA】"] # 至少有底本及 CBETA 兩個版本
    doc.xpath('//lem|//rdg').each do |e|
      w = e['wit'].scan(/【.*?】/)
      r.merge w
    end
    r
  end

  def handle_node(e, mode='html')
    return '' if e.comment?
    return handle_text(e, mode) if e.text?
    return '' if PASS.include?(e.name)
    r = case e.name
    when 'anchor'    then e_anchor(e, mode)
    when 'app'       then e_app(e, mode)
    when 'bibl'      then html_span(e, mode)
    when 'biblScope' then html_span(e, mode)
    when 'byline'    then e_byline(e, mode)
    when 'caesura'   then e_caesura(e, mode)
    when 'cell'      then e_cell(e)
    when 'corr'      then e_corr(e, mode)
    when 'div'       then e_div(e, mode)
    when 'entry'     then html_span(e, mode)
    when 'foreign'   then e_foreign(e, mode)
    when 'formula'   then html_span(e, mode)
    when 'g'         then e_g(e, mode)
    when 'graphic'   then e_graphic(e)
    when 'head'      then e_head(e, mode)
    when 'hi'        then html_span(e, mode)
    when 'item'      then e_item(e, mode)
    when 'juan'      then e_juan(e, mode)
    when 'l'         then e_l(e, mode)
    when 'lb'        then e_lb(e, mode)
    when 'lem'       then e_lem(e)
    when 'lg'        then e_lg(e, mode)
    when 'list'      then e_list(e, mode)
    when 'mulu'      then e_mulu(e, mode)
    when 'note'      then e_note(e, mode)
    when 'milestone' then e_milestone(e)
    when 'p'         then e_p(e, mode)
    when 'pb'        then e_pb(e, mode)
    when 'rdg'       then e_rdg(e)
    when 'ref'       then e_ref(e)
    when 'reg'       then e_reg(e)
    when 'row'       then e_row(e)
    when 'seg'       then html_span(e, mode)
    when 'sic'       then e_sic(e, mode)
    when 'sg'        then e_sg(e, mode)
    when 't'         then e_t(e, mode)
    when 'term'      then e_term(e, mode)
    when 'tt'        then e_tt(e, mode)
    when 'table'     then e_table(e)
    when 'text'      then e_text(e)
    when 'unclear'   then e_unclear(e)
    else traverse(e, mode)
    end
    r
  end
  
  def handle_text(e, mode)
    s = e.content().chomp
    return '' if s.empty?
    return '' if e.parent.name == 'app'

    # cbeta xml 文字之間會有多餘的換行
    s.gsub!(/[\n\r]/, '')
    return s if mode=='footnote'
    
    text_size = MyCbetaShare.remove_puncs(s).size
    
    if @pass.last and mode == 'html'
      r = s.gsub(/([。，、；？！：「」『』《》＜＞〈〉〔〕［］【】〖〗…—]+)/, '<span class="pc">\1</span>')
      r.gsub!(/&/, '&amp;')
    else
      # 把 & 轉為 &amp;
      r = CGI.escapeHTML(s)
    end

    # 正文區的文字外面要包 span
    if @pass.last and mode=='html'
      node = HtmlNode.new('span')
      node['class'] = 't'
      node['l'] = @lb
      node['w'] = @char_count
      node.content = r
      r = node.to_s
      @char_count += text_size
    end
    r
  end
  
  def html_back(juan_no)
    r = @back[juan_no]
    @notes_mod[juan_no].each_pair do |k,v|
      r += "<span class='footnote' id='n#{k}'>#{v}</span>\n"
    end
    r += @notes_add[juan_no].join("\n")
    r
  end

  def html_span(e, mode)
    s = traverse(e, mode)
    return s if mode=='footnote'

    span = HtmlNode.new('span')
    span.content = s

    if e.key? 'style'
      span['style'] = e['style']
    end

    if e.key? 'rend'
      span['class'] = e['rend']
    end

    span.to_s
  end
  
  def lem_note_cf(e)
    # ex: T32n1670A.xml, p. 703a16
    # <note type="cf1">K30n1002_p0257a01-a23</note>
    refs = []
    e.xpath('./note').each { |n|
      if n.key?('type') and n['type'].start_with? 'cf'
        s = n.content
        if linehead_exist_in_cbeta(s)
          s = "<span class='note_cf'>#{s}</span>"
        end
        refs << s
      end
    }
    if refs.empty?
      ''
    else
      '修訂依據：' + refs.join('；') + '。'
    end
  end

  def lem_note_rdg(lem)
    r = ''
    app = lem.parent
    @pass << false
    app.xpath('rdg').each { |rdg|
      if rdg['wit'].include? @orig
        s = traverse(rdg, 'footnote')
        s = MISSING if s.empty?
        r += @orig + s
      end
    }
    @pass.pop
    r += '。' unless r.empty?
    r
  end

  def line_info
    "<span class='lineInfo' line='#{@lb}'></span>"
  end

  # 用於依原書換行的空格
  def line_space(s)
    i = s.to_i
    return '' if i <= 0
    "<span class='line_space' data-size='#{i}'></span>"
  end
  
  def linehead_exist_in_cbeta(s)
    fn = CBETA.linehead_to_xml_file_path(s)
    return false if fn.nil?
    
    path = File.join(@xml_root, fn)
    File.exist? path
  end

  def open_xml(fn)
    s = File.read(fn)

    if fn.include? 'T16n0657'
      # 這個地方 雙行夾註 跨兩行偈頌
      # 把 lb 移到 note 結束之前
      # 讓 lg-row 先結束，再結束雙行夾註
      s.sub!(/(<\/note>)(\n<lb n="0206b29" ed="T"\/>)/, '\2\1')
    end

    # 2018 Q3 開始 milestone 規則改變
    # <milestone unit="juan"> 前面的 lb 屬於新的這一卷
    #s.gsub!(%r{((?:<pb [^>]+>\n?)?(?:<lb [^>]+>\n?)+)(<milestone [^>]*unit="juan"[^/>]*/>)}, '\2\1')

    doc = Nokogiri::XML(s)
    doc.remove_namespaces!()
    doc
  end

  def read_mod_notes(doc)
    doc.xpath("//note[@type='mod']").each { |e|
      @mod_notes << e['n']
    }
  end
  
  def rend_to_css(rend)
    a = rend.split(';')
    a2 = []
    a.each do |s|
      if s.start_with? 'margin-left' or s.start_with? 'text-indent'
        a2 << s
      end
    end
    a2.join(';')
  end

  def parse_xml(xml_fn)
    @pass = [false]

    doc = open_xml(xml_fn)
    
    e = doc.xpath("//titleStmt/title")[0]
    @title = traverse(e, 'txt')
    @title = @title.split()[-1]
    
    e = doc.at_xpath("//projectDesc/p[@lang='zh-Hant']")
    abort "找不到貢獻者" if e.nil?
    @contributors = e.text
    
    @punc_resp = 'orig'
    e = doc.at_xpath("//editorialDecl/punctuation")
    unless e.nil?
      @punc_resp = e['resp']
    end

    read_mod_notes(doc)

    root = doc.root()
    text_node = root.at_xpath("text")
    @pass = [true]
    
    @editions = get_editions(doc)

    text = handle_node(text_node)
    text
  end
  
  def progress(msg)
    $stderr.puts Time.now.strftime("%Y-%m-%d %H:%M:%S")
    $stderr.puts msg
  end

  def stat_jm_facs
    i = 0
    @jm_facsimile.each_pair do |k,v|
      i += v.size
    end
    $stderr.print "\n#{i} 幅嘉興藏圖像的連結，"
    $stderr.puts "分佈於 #{@jm_facsimile.size} 部典籍 #{@j_facs_juans.size} 卷中。"
    $stderr.puts "新文豐嘉興藏 pb 數量：#{@j_pages}，相當於民族出版社版頁數：#{@j_pages * 3}"
  end

  #def readings_to_note(readings)
  #  r = ''
  #  readings.each do |reading|
  #    w = reading[:wit].sub(/【麗】/, '【麗-CB】')
  #    w.sub!(/【CBETA】/, '【CB】')
  #    s = reading[:text]
  #    s1 = s.gsub(/<a class='gaijiAnchor' href='.*?'>(.*?)<\/a>/, '\1')
  #    s1.gsub!(/<span class='siddam'[^>]*?>/, '')
  #    if s1.include? '<'
  #      puts "app@n: #{@app_n}"
  #      puts s1
  #      abort
  #    end
  #    r += "<tr><td>#{w}</td><td>#{s}</td></tr>"
  #  end
  #  %(<table class="app">#{r}</table>)
  #end
  
  def to_html(e)
    e.to_xml(
      encoding: 'UTF-8',
      save_with: Nokogiri::XML::Node::SaveOptions::AS_XML |
                 Nokogiri::XML::Node::SaveOptions::NO_EMPTY_TAGS
    )
  end

  def traverse(e, mode='html')
    pass = @pass.last
    pass = false if mode == 'footnote'
    @pass << pass
    
    r = ''
    e.children.each { |c| 
      s = handle_node(c, mode)
      r += s
    }
    @pass.pop
    r
  end

  def write_juan(folder, juan_no, html)
    if @sutra_no.match(/^(T05|T06|T07)n0220/)
      work = "T0220"
    else
      work = @sutra_no.sub(/^([A-Z]{1,2})\d{2,3}n(.*)$/, '\1\2')
    end
    juan = "%03d" % juan_no
    
    #progress "filter html ed: #{ed}"
    back = html_back(juan_no)
          
    # 如果是卷跨冊的上半部
    if (work=='L1557' and @vol=='L130' and juan_no==17) or
       (work=='L1557' and @vol=='L131' and juan_no==34) or
       (work=='L1557' and @vol=='L132' and juan_no==51) or
       (work=='X0714' and @vol=='X39' and juan_no==3)
       @html_buf = html
       @back_buf = back
    else    
      body = html
      unless @html_buf.empty?
        body = @html_buf + body
        @html_buf = ''
      end
      back = @back_buf + back unless @back_buf.empty?
      copyright = html_copyright(work, juan_no)
      fn = File.join(folder, "#{juan}.html")
      write_juan_file(fn, body, back, copyright)
      
      @back_buf = ''
    end
  end
  
  def write_juan_file(fn, body, back, copyright)
    text = <<eos
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<title>#{@title}</title>
</head>
<body>
<div id='body' data-punc="#{@punc_resp}">#{body}</div>
<div id='back'>
  #{back}
</div>
#{copyright}
</body></html>
eos
    File.write(fn, text)
  end
  
  include P5aToHtmlShare
  include CbetaP5aShare

end