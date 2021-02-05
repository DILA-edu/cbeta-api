require 'cgi'
require 'date'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'set'
require 'cbeta'
require_relative 'html-node'
require_relative 'x2h_share'
require_relative 'share'

# Convert CBETA XML P5a to HTML for every edition
#
# 例如 T0001 長阿含經 有 CBETA、元、宋、聖、磧砂、unknown、大、明、麗等版本，
# 每一個版本都會輸出一個 HTML 檔，以版本為檔名。
#
# CBETA XML P5a 可由此取得: https://github.com/cbeta-git/xml-p5a
#
# 轉檔規則請參考: http://wiki.ddbc.edu.tw/pages/CBETA_XML_P5a_轉_HTML
class P5aToHTMLForEveryEdition
  # 內容不輸出的元素
  PASS=['back', 'teiHeader']
  
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
    @gaijis = CBETA::Gaiji.new
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
    return convert_all if target.nil?

    arg = target.upcase
    if arg.size.between?(1,2)
      convert_canon(arg)
    else
      puts "因為某些典籍單卷跨冊，轉檔必須以某部藏經為單位，例如參數 T 表示轉換整個大正藏。"
    end
  end

  private
  
  include CbetaShare
  
  def before_parse_xml(xml_fn)
    @back = { 0 => '' }
    @back_orig = { 0 => '' }
    @char_count = 1
    @dila_note = 0
    @div_count = 0
    @in_l = false
    @juan = 0
    @lg_row_open = false
    @mod_notes = Set.new
    @next_line_buf = ''
    @notes_mod = {}
    @notes_orig = {}
    @notes_dila = {}
    @open_divs = []
    @sutra_no = File.basename(xml_fn, ".xml")
    print @sutra_no + ' '
    @updated_at = MyCbetaShare.get_update_date(xml_fn)
  end

  def convert_all
    Dir.entries(@xml_root).sort.each do |c|
      next unless c.match(/^#{CBETA::CANON}$/)
      convert_canon(c)
    end
  end
  
  def convert_canon(c)
    @series = c
    puts 'convert canon: ' + c
    folder = File.join(@xml_root, @series)
    
    @out_folder = File.join(@out_root, @series)
    FileUtils::rm_rf @out_folder
    FileUtils::mkdir_p @out_folder
    
    @html_buf = {}
    @back_buf = {}
    
    Dir.entries(folder).sort.each do |vol|
      next if vol.start_with? '.'
      convert_vol(vol)
    end
  end
  
  def convert_sutra(xml_fn)
    before_parse_xml(xml_fn)

    text = parse_xml(xml_fn)

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
        write_juan(juan_no, buf+j)
        buf = ''
      end
    }
  end  
  
  def convert_vol(vol)
    puts "convert volumn: #{vol}"
    
    canon = CBETA.get_canon_from_vol(vol)
    @orig = @cbeta.get_canon_symbol(canon)
    abort "未處理底本" if @orig.nil?
    @orig_short = @orig.sub(/^【(.*)】$/, '\1')

    @vol = vol
    
    source = File.join(@xml_root, @series, vol)
    Dir.entries(source).sort.each do |f|
      next if f.start_with? '.'
      fn = File.join(source, f)
      convert_sutra(fn)
    end
  end
  
  def e_anchor(e)
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

  def e_app(e)
    r = ''
    if e['type'] == 'star'
      c = e['corresp'][1..-1]
      r = "<a class='noteAnchor star' href='#n#{c}'></a>"
    end
    r + traverse(e)
  end

  def e_byline(e)
    r = '<p class="byline">'
    r += line_info
    r += traverse(e)
    r + '</p>'
  end

  def e_cell(e)
    doc = Nokogiri::XML::Document.new
    cell = doc.create_element('div')
    cell['class'] = 'bip-table-cell'
    cell['rowspan'] = e['rows'] if e.key? 'rows'
    cell['colspan'] = e['cols'] if e.key? 'cols'
    cell.inner_html = traverse(e)
    to_html(cell)
  end

  def e_corr(e)
    r = ''
    if e.parent.name == 'choice'
      sic = e.parent.at_xpath('sic')
      unless sic.nil?
        n = @notes_dila[@juan].size + 1
        r = "<a class='noteAnchor dila' href='#dila_note#{n}'></a>"

        note = @orig
        sic_text = traverse(sic, 'back')
        if sic_text.empty?
          note += MISSING
        else
          note += sic_text
        end
        @notes_dila[@juan] << "<span class='footnote dila' id='dila_note#{n}'>#{note}</span>"
      end
    end
    r + "<r w='【CBETA】' l='#{@lb}'><span class='cbeta'>%s</span></r>" % traverse(e)
  end

  def e_div(e)
    @div_count += 1
    n = @div_count
    if e.has_attribute? 'type'
      @open_divs << e
      r = traverse(e)
      @open_divs.pop
      return "<!-- begin div#{n}--><div class='div-#{e['type']}'>#{r}</div><!-- end of div#{n} -->"
    else
      return traverse(e)
    end
  end

  def e_g(e, mode)
    # if 有 <mapping type="unicode">
    #   if 不在 Unicode Extension C, D, E 範圍裡
    #     直接採用
    #   else
    #     預設呈現 unicode, 但仍包缺字資訊，供點選開 popup
    # else if 有 <mapping type="normal_unicode">
    #   預設呈現 normal_unicode, 但仍包缺字資訊，供點選開 popup
    # else if 有 normalized form
    #   預設呈現 normalized form, 但仍包缺字資訊，供點選開 popup
    # else
    #   預設呈現組字式, 但仍包缺字資訊，供點選開 popup
    gid = e['ref'][1..-1]
    g = @gaijis[gid]
    abort "Line:#{__LINE__} 無缺字資料:#{gid}" if g.nil?
    zzs = g['zzs']
    
    if mode == 'txt'
      return g['roman'] if gid.start_with?('SD')
      if zzs.nil?
        abort "缺組字式：#{g}"
      else
        return zzs
      end
    end

    @char_count += 1

    if gid.start_with?('SD')
      case gid
      when 'SD-E35A'
        return '（'
      when 'SD-E35B'
        return '）'
      else
        return "<span class='siddam' roman='#{g['roman']}' code='#{gid}' char='#{g['sd-char']}'/>"
      end
    end
    
    if gid.start_with?('RJ')
      return "<span class='ranja' roman='#{g['roman']}' code='#{gid}' char='#{g['rj-char']}'/>"
    end
   
    default = ''
    span = HtmlNode.new('span')
    if g.has_key?('unicode')
      span['unicode'] = g['unicode']
      #if @unicode1.include?(g['unicode'])
      # 如果在 unicode ext-C, ext-D, ext-E 範圍內
      if (0x2A700..0x2EBEF).include? g['unicode'].hex
        default = g['unicode-char']
      else
        return g['unicode-char'] # 直接採用 unicode
      end
    end

    nor = ''
    if g.has_key?('normal_unicode')
      nor = g['normal_unicode']
      default = nor if default.empty?
    end

    if g.has_key?('normal')
      nor += ', ' unless nor==''
      nor += g['normal']
      default = g['normal'] if default.empty?
    end

    if default.empty?
      abort "缺組字式：#{gid}" if zzs.blank?
      default = zzs
    end
    
    href = 'http://dict.cbeta.org/dict_word/gaiji-cb/%s/%s.gif' % [gid[2, 2], gid]
    
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
    url = File.basename(e['url'])
    "<span imgsrc='#{url}' class='graphic'></span>"
  end

  def e_head(e)
    r = ''
    unless e['type'] == 'added'
      i = @open_divs.size
      r = "<p class='head' data-head-level='#{i}'>%s</p>" % traverse(e)
    end
    r
  end

  def e_item(e)
    "<li>%s</li>\n" % traverse(e)
  end

  def e_juan(e)
    "<p class='juan'>%s</p>" % traverse(e)
  end

  def e_l(e)
    if @lg_type == 'abnormal'
      return traverse(e)
    end

    @in_l = true

    doc = Nokogiri::XML::Document.new
    cell = doc.create_element('div')
    cell['class'] = 'lg-cell'
    cell.inner_html = traverse(e)
    
    if @first_l
      parent = e.parent()
      if parent.has_attribute?('rend')
        indent = parent['rend'].scan(/text-indent:[^:]*/)
        unless indent.empty?
          cell['style'] = indent[0]
        end
      end
      @first_l = false
    end
    r = to_html(cell)
    
    unless @lg_row_open
      r = "\n<div class='lg-row'>" + r
      @lg_row_open = true
    end
    @in_l = false
    r
  end

  def e_lb(e)
    return '' if e['type']=='old'
    return '' if e['ed'] != @series
    
    @lb_r = nil
    # 卍續藏有 X 跟 R 兩種 lb
    if @series=='X'
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
    #if e.parent.name == 'lg' and $lg_row_open
    if @lg_row_open && !@in_l
      # 每行偈頌放在一個 lg-row 裡面
      # T46n1937, p. 914a01, l 包雙行夾註跨行
      # T20n1092, 337c16, lb 在 l 中間，不結束 lg-row
      r += "</div><!-- end of lg-row -->"
      @lg_row_open = false
    end
    
    doc = Nokogiri::XML::Document.new
    node = doc.create_element('span')
    node['class'] = 'lb'
    node['class'] += ' honorific' if e['type'] == 'honorific'
    node['id'] = line_head
    node['data-lr'] = @lb_r unless @lb_r.nil?
    node.inner_html = line_head
    r += to_html(node)
    
    unless @next_line_buf.empty?
      r += @next_line_buf
      @next_line_buf = ''
    end
    r
  end

  def e_lem(e)
    r = ''
    content = traverse(e)
    wit = e['wit']
    if wit.include? 'CBETA' and not wit.include? @orig
      #n = @notes_dila[@juan].size + 1
      #r = "<a class='noteAnchor dila' href='#dila_note#{n}'></a>"
      r += "<span class='cbeta'>%s</span>" % content
      r = "<r w='#{wit}' l='#{@lb}'>#{r}</r>"

      #note = lem_note_cf(e)
      #note += lem_note_rdg(e)
      #@notes_dila[@juan] << "<span class='footnote dila' id='dila_note#{n}'>#{note}</span>"
    end
    
    # 沒有 rdg 的版本，用字同 lem
    editions = Set.new @editions
    e.xpath('./following-sibling::rdg').each do |rdg|
      rdg['wit'].scan(/【.*?】/).each do |w|
        editions.delete w
      end
    end
    
    editions.delete('【CBETA】') unless r.empty?
    w = editions.to_a.join(' ')
    r + ("<r w='#{w}' l='#{@lb}'>%s</r>" % content)
  end

  def e_lg(e)
    r = ''
    @lg_type = e['type']
    if @lg_type == 'abnormal'
      r = "<p class='lg-abnormal'>" + traverse(e) + "</p>"
    else
      @first_l = true
      doc = Nokogiri::XML::Document.new
      node = doc.create_element('div')
      node['class'] = 'lg'
      if e.has_attribute?('rend')
        rend = e['rend'].gsub(/text-indent:[^:]*/, '')
        node['style'] = rend
      end
      @lg_row_open = false
      node.inner_html = traverse(e)
      if @lg_row_open
        node.inner_html += '</div><!-- end of lg -->'
        @lg_row_open = false
      end
      r = "\n" + to_html(node)
    end
    r
  end

  def e_list(e)
    "<ul>%s</ul>" % traverse(e)
  end

  def e_milestone(e)
    r = ''
    if e['unit'] == 'juan'

      r += "</div>" * @open_divs.size  # 如果有 div 跨卷，要先結束, ex: T55n2154, p. 680a29, 跨 19, 20 兩卷
      @juan = e['n'].to_i
      @back[@juan] = @back[0]
      @back_orig[@juan] = @back_orig[0]
      @notes_mod[@juan] = {}
      @notes_orig[@juan] = {}
      @notes_dila[@juan] = []
      r += "<juan #{@juan}>"
      @open_divs.each { |d|
        r += "<div class='div-#{d['type']}'>"
      }
    end
    r
  end

  def e_mulu(e)
    r = ''
    if e['type'] == '品'
      @pass << false
      r = "<mulu class='pin' s='%s'/>" % traverse(e, 'txt')
      @pass.pop
    end
    r
  end
  

  def e_note(e)
    n = e['n']
    if e.has_attribute?('type')
      t = e['type']
      case t
      when 'equivalent'
        return ''
      when 'orig'
        return handle_note_orig(e)
      when 'orig_biao'
        return handle_note_orig(e, 'biao')
      when 'orig_ke'
        return handle_note_orig(e, 'ke')
      when 'mod'
        @pass << false
        s = traverse(e)
        @pass.pop
        #@back[@juan] = "<span class='footnote_cb' id='n#{n}'>#{s}</span>\n"
        @notes_mod[@juan][n] = s
        return "<r w='【CBETA】'><a class='noteAnchor cb' href='#n#{n}'></a></r>"
      when 'rest'
        return ''
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
      when 'inline' then 'doube-line-note'
      end
      
      return "<span class='#{c}'>#{r}</span>"
    else
      return traverse(e)
    end
  end


  def e_p(e)
    if e.key? 'type'
      r = "<p class='%s'>" % e['type']
    else
      r = '<p>'
    end
    r += line_info
    r += traverse(e)
    r + '</p>'
  end
  
  def e_rdg(e)
    r = traverse(e)
    "<r w='#{e['wit']}' l='#{@lb}' w='#{@char_count}'>#{r}</r>"
  end

  def e_row(e)
    "<div class='bip-table-row'>" + traverse(e) + "</div>"
  end

  def e_sg(e)
    '(' + traverse(e) + ')'
  end
  
  def e_sic(e)
    "<r w='#{@orig}' l='#{@lb}'>" + traverse(e) + "</r>"
  end

  def e_t(e)
    if e.has_attribute? 'place'
      return '' if e['place'].include? 'foot'
    end
    r = traverse(e)

    # <tt type="app"> 不是 悉漢雙行對照
    return r if @tt_type == 'app'

    # 處理雙行對照
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

  def e_tt(e)
    @tt_type = e['type']
    traverse(e)
  end

  def e_table(e)
    "<div class='bip-table'>" + traverse(e) + "</div>"
  end
  
  def e_unclear(e)
    '▆'
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

  def handle_node(e, mode)
    return '' if e.comment?
    return handle_text(e, mode) if e.text?
    return '' if PASS.include?(e.name)
    r = case e.name
    when 'anchor'    then e_anchor(e)
    when 'app'       then e_app(e)
    when 'byline'    then e_byline(e)
    when 'cell'      then e_cell(e)
    when 'corr'      then e_corr(e)
    when 'div'       then e_div(e)
    when 'foreign'   then ''
    when 'g'         then e_g(e, mode)
    when 'graphic'   then e_graphic(e)
    when 'head'      then e_head(e)
    when 'item'      then e_item(e)
    when 'juan'      then e_juan(e)
    when 'l'         then e_l(e)
    when 'lb'        then e_lb(e)
    when 'lem'       then e_lem(e)
    when 'lg'        then e_lg(e)
    when 'list'      then e_list(e)
    when 'mulu'      then e_mulu(e)
    when 'note'      then e_note(e)
    when 'milestone' then e_milestone(e)
    when 'p'         then e_p(e)
    when 'rdg'       then e_rdg(e)
    when 'reg'       then ''
    when 'row'       then e_row(e)
    when 'sic'       then e_sic(e)
    when 'sg'        then e_sg(e)
    when 't'         then e_t(e)
    when 'tt'        then e_tt(e)
    when 'table'     then e_table(e)
    when 'unclear'   then e_unclear(e)
    else traverse(e)
    end
    r
  end
  
  def handle_note_orig(e, anchor_type=nil)
    n = e['n']
    @pass << false
    s = traverse(e)
    @pass.pop
    @notes_orig[@juan][n] = s
    @notes_mod[@juan][n] = s
    
    c = @series
    
    # 如果 CBETA 沒有修訂，就跟底本的註一樣
    # 但是 CBETA 修訂後的編號，有時會加上 a, b
    # T01n0026, p. 506b07, 大正藏校勘 0506007, CBETA 拆為 0506007a, 0506007b
    c += " cb" unless @mod_notes.include?(n) or @mod_notes.include?(n+'a')

    label = case anchor_type
    when 'biao' then " data-label='標#{n[-2..-1]}'"
    when 'ke'   then " data-label='科#{n[-2..-1]}'"
    else ''
    end
    s = "<a class='noteAnchor #{c}' href='#n#{n}'#{label}></a>"
    r = "<r w='#{@orig}'>#{s}</r>"
    
    unless @mod_notes.include?(n)
      r += "<r w='【CBETA】'>#{s}</r>"
    end
    r
  end
  
  def handle_text(e, mode)
    s = e.content().chomp
    return '' if s.empty?
    return '' if e.parent.name == 'app'

    # cbeta xml 文字之間會有多餘的換行
    s.gsub!(/[\n\r]/, '')
    
    text_size = s.size
    
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
  
  def html_back(juan_no, ed)
    #progress "html back, juan: #{juan_no}, ed: #{ed}"
    r = ''
    case ed
    when '【CBETA】'
      r = @back[juan_no]
      @notes_mod[juan_no].each_pair do |k,v|
        r += "<span class='footnote cb' id='n#{k}'>#{v}</span>\n"
      end
      r += @notes_dila[juan_no].join("\n")
    when @orig
      r = @back_orig[juan_no]
      @notes_orig[juan_no].each_pair do |k,v|
        r += "<span class='footnote #{@series}' id='n#{k}'>#{v}</span>\n"
      end
    end
    r
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
        s = traverse(rdg, 'back')
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

    # <milestone unit="juan"> 前面的 lb 屬於新的這一卷
    s.gsub!(%r{((?:<pb [^>]+>\n?)?(?:<lb [^>]+>\n?)+)(<milestone [^>]*unit="juan"[^/>]*/>)}, '\2\1')

    doc = Nokogiri::XML(s)
    doc.remove_namespaces!()
    doc
  end

  def read_mod_notes(doc)
    doc.xpath("//note[@type='mod']").each { |e|
      @mod_notes << e['n']
    }
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
    
    read_mod_notes(doc)

    root = doc.root()
    body = root.xpath("text/body")[0]
    @pass = [true]
    
    @editions = get_editions(doc)

    text = traverse(body)
    text
  end
  
  def progress(msg)
    puts Time.now.strftime("%Y-%m-%d %H:%M:%S")
    puts msg
  end
  
  def to_html(e)
    e.to_xml(
      encoding: 'UTF-8',
      save_with: Nokogiri::XML::Node::SaveOptions::AS_XML |
                 Nokogiri::XML::Node::SaveOptions::NO_EMPTY_TAGS
    )
  end

  def traverse(e, mode='html')
    r = ''
    e.children.each { |c| 
      s = handle_node(c, mode)
      r += s
    }
    r
  end
  
  def write_juan(juan_no, html)
    if @sutra_no.match(/^(T05|T06|T07)n0220/)
      work = "T0220"
    else
      work = @sutra_no.sub(/^([A-Z]{1,2})\d{2,3}n(.*)$/, '\1\2')
    end
    juan = "%03d" % juan_no
    folder = File.join(@out_folder, work, juan)
    FileUtils.remove_dir(folder, true)
    FileUtils.makedirs folder
    
    @editions.each do |ed|
      #progress "filter html ed: #{ed}"
      ed_html = filter_html(html, ed)
      back = html_back(juan_no, ed)
            
      # 如果是卷跨冊的上半部
      if (work=='L1557' and @vol=='L130' and juan_no==17) or
         (work=='L1557' and @vol=='L131' and juan_no==34) or
         (work=='L1557' and @vol=='L132' and juan_no==51) or
         (work=='X0714' and @vol=='X39' and juan_no==3)
         @html_buf[ed] = ed_html
         @back_buf[ed] = back
         next
      else    
        body = ed_html
        unless @html_buf.empty?
          body = @html_buf[ed] + body
          @html_buf.delete ed
        end
        back = @back_buf[ed] + back unless @back_buf.empty?
        copyright = html_copyright(work, juan_no)
        write_juan_ed(folder, ed, body, back, copyright)
        
        @back_buf.delete ed
      end
    end
  end
  
  def write_juan_ed(folder, ed, body, back, copyright)
    fn = ed.sub(/^【(.*)】$/, '\1')
    if fn != 'CBETA' and fn != @orig_short
      fn = @orig_short + '→' + fn
    end
    fn += '.htm'
    output_path = File.join(folder, fn)
    text = <<eos
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<title>#{@title}</title>
</head>
<body>
<div id='body'>#{body}</div>
<div id='back'>
  #{back}
</div>
#{copyright}
</body></html>
eos
    File.write(output_path, text)
  end
  
  include P5aToHtmlShare

end