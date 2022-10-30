require 'cgi'
require 'date'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'set'
require 'zip'
require_relative 'html-node'
require_relative 'x2h_share'
require_relative 'cbeta_p5a_share'
require_relative 'share'

# Convert CBETA XML P5a to HTML
#
# CBETA XML P5a 可由此取得: https://github.com/cbeta-git/xml-p5a
#
# 轉檔規則請參考: http://wiki.dila.edu.tw/pages/CBETA_XML_P5a_轉_HTML
class P5aToHTMLForDownload
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
    @us = UnicodeService.new
    
    FileUtils.rm_rf @out_root
    FileUtils::mkdir_p @out_root
  end

  # 將 CBETA XML P5a 轉為 HTML
  #
  # @example for convert 大正藏第一冊:
  #
  #   x2h = CBETA::P5aToHTML.new('/PATH/TO/CBETA/XML/P5a', '/OUTPUT/FOLDER')
  #   x2h.convert('T01')
  #
  # @example for convert 大正藏全部:
  #
  #   x2h = CBETA::P5aToHTML.new('/PATH/TO/CBETA/XML/P5a', '/OUTPUT/FOLDER')
  #   x2h.convert('T')
  #
  # @example for convert 大正藏第五冊至第七冊:
  #
  #   x2h = CBETA::P5aToHTML.new('/PATH/TO/CBETA/XML/P5a', '/OUTPUT/FOLDER')
  #   x2h.convert('T05..T07')
  #
  # T 是大正藏的 ID, CBETA 的藏經 ID 系統請參考: http://www.cbeta.org/format/id.php
  def convert(target=nil)
    puts "x2h_for_download target: #{target}"
    return convert_all if target.nil?

    arg = target.upcase
    if arg.size <= 2
      handle_collection(arg)
    else
      if arg.include? '..'
        arg.match(/^([^\.]+?)\.\.([^\.]+)$/) {
          handle_vols($1, $2)
        }
      else
        handle_vol(arg)
      end
    end
  end

  private
  
  def convert_all
    each_canon(@xml_root) do |c|
      handle_collection(c)
    end
  end

  def e_anchor(e)
    id = e['id']
    if e.has_attribute?('id')
      if id.start_with?('nkr_note_orig')
        return ""
      elsif id.start_with? 'fx'
        return ""
      end
    end

    if e.has_attribute?('type')
      if e['type'] == 'circle'
        return ''
      end
    end

    ''
  end

  def e_app(e)
    r = ''
    if e['type'] == 'star'
      r = ""
    end
    r + traverse(e)
  end

  def e_byline(e)
    node = HtmlNode.new('p')
    classes = ['byline']
    classes << e['rend'] if e.key? 'rend'
    node['class'] = classes.join(' ')
    node.content = line_info + traverse(e)
    node.to_s + "\n"
  end

  def e_caesura(e, mode)
    if e.key?('style')
      e['style'].match(/text-indent:(\d+)em/) do
        return '　' * ($1.to_i)
      end
    else
      return '　　'
    end
    ''
  end

  def e_cell(e)
    cell = HtmlNode.new('div')
    cell['class'] = 'bip-table-cell'
    cell['rowspan'] = e['rows'] if e.key? 'rows'
    cell['colspan'] = e['cols'] if e.key? 'cols'
    cell['style'] = e['style']  if e.key? 'style'
    cell.content = traverse(e)
    cell.to_s
  end

  def e_corr(e)
    traverse(e)
  end

  def e_div(e)
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
    g = gid.start_with?('CB') ? @gaijis[gid] : @gaijis_skt[gid]
    abort "Line:#{__LINE__} 無缺字資料:#{gid}" if g.nil?
    
    if mode == 'txt'
      if gid.start_with?('SD') or gid.start_with?('RJ')
        return g['symbol'] unless g['symbol'].blank?
        return g['romanized'] unless g['romanized'].blank?
        return "[#{gid}]"
      else
        return g['uni_char'] if @us.level1?(g['unicode'])
        return g['norm_uni_char'] if @us.level1?(g['norm_unicode'])
        return g['norm_big5_char'] unless g['norm_big5_char'].blank?
        if g['composition'].blank?
          abort "缺組字式：#{gid}"
        else
          return g['composition']
        end
      end
    end

    if gid.start_with?('SD')
      return g['symbol'] unless g['symbol'].blank?
      return "<span class='siddam' roman='#{g['romanized']}' code='#{gid}' char='#{g['char']}'/>"
    end
    
    if gid.start_with?('RJ')
      return "<span class='ranja' roman='#{g['romanized']}' code='#{gid}' char='#{g['char']}'/>"
    end
   
    default = ''
    if @us.level1?(g['unicode'])
      return g['uni_char'] # 直接採用 unicode
    elsif @us.level2?(g['unicode'])
      default = g['uni_char']
    end

    nor = ''
    if @gaiji_norm.last # 如果沒有特別指定不能用通用字
      unless g['norm_uni_char'].blank?
        nor = g['norm_uni_char'].clone
        if default.empty?
          default = nor.clone if @us.level2?(g['norm_unicode'])
        end
      end

      c = g['norm_big5_char']
      unless c.blank?
        nor << ', ' unless nor==''
        nor << c
        default = c if default.empty?
      end
    end

    default = g['composition'] if default.empty?
    %(<span class="gaiji" data-gid="#{gid}">#{default}</span>)
  end

  def e_graphic(e)
    url = File.basename(e['url'])

    mime = case File.extname(url)
    when '.svg' then 'image/svg+xml'
    else 'image/gif'
    end

    canon = url.sub(/^(\D+)\d.*$/, '\1')
    fn = File.join(Rails.configuration.x.figures, canon, url)
    b = IO.read(fn)
    s = Base64.encode64(b)
    %(<img src="data:#{mime};base64,#{s}" />)
  end

  def e_head(e, mode)
    return traverse(e, mode) if mode=='footnote'
    return '' if e['type'] == 'added'

    node = HtmlNode.new('p')
    node.content = traverse(e, mode)
    node['data-head-level'] = @open_divs.size

    classes = ['head']

    if e.key?('rend')
      classes << e['rend']
    end

    node['class'] = classes.join(' ')

    node.to_s
  end

  def e_item(e)
    s = traverse(e)
    li = HtmlNode.new('li')
    
    # ex: T18n0850_p0087a14
    if e.key? 'n'
      n = e['n']
      i = n.size
      s = n + s
      li['style'] = "margin-left:#{i}em;text-indent:-#{i}em"
    end
    
    li.content = s
    li.to_s + "\n"
  end

  def e_juan(e)
    "<p class='juan'>%s</p>" % traverse(e)
  end

  def e_lb(e)
    return '' if e['type']=='old'
    
    # 卍續藏有 X 跟 R 兩種 lb, 只處理 X
    return '' if e['ed'] != @series

    @lb = e['n']
    
    r = ''
    r = "\n" if @pre.last

    unless @next_line_buf.empty?
      r << @next_line_buf
      @next_line_buf = ''
    end
    r
  end

  def e_lem(e)
    traverse(e)
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

  def e_list(e)
    ul = HtmlNode.new('ul')
    ul['class'] = e['rend'] if e.key? 'rend'
    
    # ex: T18n0850_p0087a14
    item = e.at_xpath('descendant::item') # item 可能在 app 裡
    if item.key? 'n'
      ul['style'] = "list-style-type:none;margin-left:0;padding-left:0"
    end
    
    ul.content = traverse(e)
    ul.to_s
  end

  def e_milestone(e)
    r = ''
    if e['unit'] == 'juan'

      r << "</div>" * @open_divs.size  # 如果有 div 跨卷，要先結束, ex: T55n2154, p. 680a29, 跨 19, 20 兩卷
      @juan = e['n'].to_i
      @back[@juan] = @back[0]
      @back[0] = ''
      @notes_mod[@juan] = {}
      @notes_orig[@juan] = {}
      
      # 如果是 卷 跨 冊，下半部編號繼續編
      unless juan_cross_vol(@vol, @work_id, @juan)==2
        @notes_add[@juan] = []
      end

      r << "<juan #{@juan}>"
      @open_divs.each { |d|
        r << "<div class='div-#{d['type']}'>"
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
  
  def e_note(e, mode=nil)
    return e_note_foot(e) if mode == 'footnote'
    return '' if e['rend'] == 'hide'

    n = e['n']
    if e.has_attribute?('type')
      t = e['type']
      case t
      when 'add'        then return e_note_add(e)
      when 'equivalent' then return ''
      when 'orig'       then return e_note_orig(e)
      when 'mod'        then return e_note_mod(e)
      when 'rest'       then return ''
      when 'star'
        href = 'n' + e['corresp'].delete_prefix('#')
        return "<a class='noteAnchor star' href='##{href}'>[＊]</a>"
      else
        return '' if t.start_with?('cf')
      end
    end

    if e.has_attribute?('resp')
      return '' if e['resp'].start_with? 'CBETA'
    end

    r = traverse(e)
    if e.has_attribute?('place')
      if e['place'].start_with? 'inline'
        r = "<span class='doube-line-note'>(#{r})</span>"
      elsif e['place']=='interlinear'
        r = "<span class='interlinear-note'>(#{r})</span>"
      end
    end
    r
  end

  def e_note_add(e)
    i = @notes_add[@juan].size + 1
    n = "cb_note_#{i}"
    s = traverse(e, 'footnote')
    s << e_note_add_cf(e)
    note = <<~HTML
      <div class='footnote' id='#{n}'>
        [<a href='#cb_note_anchor#{i}'>A#{i}</a>] #{s}
      </div>
    HTML
    @notes_add[@juan] << note
    return "<a id='cb_note_anchor#{i}' class='noteAnchor add' href='##{n}'>[A#{i}]</a>"
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
    if %w(interlinear inline inline2).include? e['place']
      return '(%s)' % traverse(e, 'footnote')
    else
      return ''
    end
  end

  def e_note_mod(e)
    n = e['n']
    @notes_mod[@juan][n] = traverse(e, 'footnote')
    i = n.last(2)
    i = i.delete_prefix('0')
    return "<a id='note_anchor_#{n}' class='noteAnchor' href='#n#{n}'>[#{i}]</a>"
  end

  def e_note_orig(e)
    n = e['n']
    subtype = e['subtype']
    s = traverse(e, 'footnote')
    @notes_orig[@juan][n] = s
    @notes_mod[@juan][n] = s

    return '' if @mod_notes.include?(n)
    
    node = HtmlNode.new('a')
    node['id'] = "note_anchor_#{n}"
    node['class'] = 'noteAnchor'
    node['href'] = "#n#{n}"

    i = n.last(2)
    node.content = case subtype
    when 'biao' then "[標#{i}]"
    when 'jie'  then "[解#{i}]"
    when 'ke'   then "[科#{i}]"
    else
      i = i.delete_prefix('0')
      "[#{i}]"
    end

    return node.to_s
  end
  
  def e_p(e, mode)
    return traverse(e, mode) if mode=='footnote'
    
    classes = []
    if e['type'] == 'pre'
      @pre << true
      node = HtmlNode.new('pre')
    else
      node = HtmlNode.new('p')
      classes << e['type'] if e.key? 'type'
    end

    # p 的 rend 屬性可能有空格隔開的多值
    classes += e['rend'].split if e.key? 'rend'
    node['class'] = classes.join(' ')

    node['style'] = e['style'] if e.key? 'style'
    
    node.content = line_info + traverse(e)
    @pre.pop if e['type'] == 'pre'
    node.to_s + "\n"
  end
  
  def e_ref(e)
    r = traverse(e)
    if e.key? 'cRef'
      t = e['cRef']
      if t.start_with? 'PTS'
        n = t.split('.').last
        r = %(<span class="hint" title="#{t}">[P.#{n}]</span>)
      end
    end
    r
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

  def e_sg(e)
    '(' + traverse(e) + ')'
  end
  
  def e_t(e)
    if e.has_attribute? 'place'
      return '' if e['place'].include? 'foot'
    end
    r = traverse(e)

    tt = e.at_xpath('ancestor::tt')
    unless tt.nil?
      # <tt type="app"> 不是 悉漢雙行對照
      return r if %w(app single-line).include? tt['type']
      return r if tt['place'] == 'inline'
      return r if tt['rend'] == 'normal'
    end
    
    if e.key? 'style'
      r = "<span style='#{e['style']}'>#{r}</span>"
    end

    # 處理雙行對照
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

  def e_term(e)
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

  def e_tt(e)
    traverse(e)
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
  
  def e_unclear(e)
    ele_unclear(e)
  end

  # 卷跨冊
  def juan_cross_vol(vol, work, juan=nil)
    case work
    when 'L1557'
      case vol
      when 'L130'
        return 1 if juan == 17 # 上半卷
      when 'L131'
        return 2 if juan.nil? or juan == 17 # 下半卷
        return 1 if juan == 34
      when 'L132'
        return 2 if juan.nil? or juan == 34
        return 1 if juan == 51
      when 'L133'
        return 2 if juan.nil? or juan == 51
      end
    when 'X0714'
      case vol
      when 'X39'
        return 1 if juan == 3
      when 'X40'
        return 2 if juan.nil? or juan == 3
      end
    end
  end

  def handle_collection(c)
    @series = c
    @canon_name = @canon_names[c]

    $stderr.puts "x2h_for_download #{c}"
    folder = File.join(@xml_root, @series)
    Dir.entries(folder).sort.each { |vol|
      next if ['.', '..', '.DS_Store'].include? vol
      handle_vol(vol)
    }
    zip_by_work(@series)
  end

  def handle_node(e, mode)
    return '' if e.comment?
    return handle_text(e, mode) if e.text?
    return '' if PASS.include?(e.name)
    r = case e.name
    when 'anchor'    then e_anchor(e)
    when 'app'       then e_app(e)
    when 'biblScope' then html_span(e, mode)
    when 'byline'    then e_byline(e)
    when 'caesura'   then e_caesura(e, mode)
    when 'cell'      then e_cell(e)
    when 'corr'      then e_corr(e)
    when 'div'       then e_div(e)
    when 'entry'     then html_span(e, mode)
    when 'foreign'   then e_foreign(e, mode)
    when 'formula'   then html_span(e, mode)
    when 'g'         then e_g(e, mode)
    when 'graphic'   then e_graphic(e)
    when 'head'      then e_head(e, mode)
    when 'hi'        then html_span(e, mode)
    when 'item'      then e_item(e)
    when 'juan'      then e_juan(e)
    when 'l'         then e_l(e, mode)
    when 'lb'        then e_lb(e)
    when 'lem'       then e_lem(e)
    when 'lg'        then e_lg(e, mode)
    when 'list'      then e_list(e)
    when 'mulu'      then e_mulu(e)
    when 'note'      then e_note(e, mode)
    when 'milestone' then e_milestone(e)
    when 'p'         then e_p(e, mode)
    when 'rdg'       then ''
    when 'reg'       then e_reg(e)
    when 'ref'       then e_ref(e)
    when 'row'       then e_row(e)
    when 'seg'       then html_span(e, mode)
    when 'sic'       then ''
    when 'sg'        then e_sg(e)
    when 't'         then e_t(e)
    when 'term'      then e_term(e)
    when 'text'      then e_text(e)
    when 'tt'        then e_tt(e)
    when 'table'     then e_table(e)
    when 'unclear'   then e_unclear(e)
    else traverse(e)
    end
    r
  end

  def handle_sutra(xml_fn)
    @back = { 0 => '' }
    @dila_note = 0
    @div_count = 0
    @gaiji_norm = [true]
    @juan = 0
    @lg_row_open = false
    @mod_notes = Set.new
    @next_line_buf = ''
    @notes_mod = {}
    @notes_orig = {}
    @open_divs = []
    @pre = [false]
    @sutra_no = File.basename(xml_fn, ".xml")
    @work_id = CBETA.get_work_id_from_file_basename(@sutra_no)
    @notes_add = {} unless juan_cross_vol(@vol, @work_id) == 2
    @updated_at = MyCbetaShare.get_update_date(xml_fn)
    
    if @sutra_no.match(/^(T05|T06|T07)n0220/)
      @sutra_no = "#{$1}n0220"
    end    
    
    @out_folder = File.join(@out_root, @series, @work_id)
    FileUtils::mkdir_p @out_folder

    text = parse_xml(xml_fn)

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
      end
    }
  end

  def handle_text(e, mode)
    s = e.content().chomp
    return '' if s.empty?
    return '' if e.parent.name == 'app'

    # cbeta xml 文字之間會有多餘的換行
    r = s.gsub(/[\n\r]/, '')

    # 把 & 轉為 &amp;
    return CGI.escapeHTML(r)
  end
  
  def handle_vol(vol)
    $stderr.puts "x2h_for_download #{vol}"
    canon = CBETA.get_canon_from_vol(vol)
    @orig = @cbeta.get_canon_abbr(canon)
    abort "未處理底本" if @orig.nil?

    @vol = vol
    @series = CBETA.get_canon_from_vol(vol)
    
    source = File.join(@xml_root, @series, vol)
    Dir[source+"/*"].sort.each { |f|
      handle_sutra(f)
    }
  end

  def handle_vols(v1, v2)
    $stderr.puts "x2h_for_download #{v1}..#{v2}"
    @series = CBETA.get_canon_from_vol(v1)
    folder = File.join(@xml_root, @series)
    Dir.foreach(folder) { |vol|
      next if vol < v1
      next if vol > v2
      handle_vol(vol)
    }
  end

  def html_back(juan_no)
    r = @back[juan_no]
    @notes_mod[juan_no].each_pair do |k,v|
      r << "<span class='footnote' id='n#{k}'><a href='#note_anchor_#{k}'>[#{k}]</a> #{v}</span>\n"
    end
    unless juan_cross_vol(@vol, @work_id, juan_no) == 1
      r << @notes_add[juan_no].join("\n") 
    end
    r
  end

  def html_span(e, mode='html')
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
        s = traverse(rdg, 'back')
        s = MISSING if s.empty?
        r << @orig + s
      end
    }
    @pass.pop
    r << '。' unless r.empty?
    r
  end

  def line_info
    "<span class='lineInfo' line='#{@lb}'></span>"
  end

  # 用於依原書換行的空格
  def line_space(s)
    ''
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
    #s.gsub!(%r{((?:<pb [^>]+>\n?)?(?:<lb [^>]+>\n?)+)(<milestone [^>]*unit="juan"[^/>]*/>)}, '\2\1')

    begin
      doc = Nokogiri::XML(s) { |config| config.strict }
    rescue Nokogiri::XML::SyntaxError => e
      puts "XML parse error, file: #{fn}"
      puts e
      abort
    end
    doc.remove_namespaces!()
    doc
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
    text_node = root.at_xpath("text")
    @pass = [true]

    text = handle_node(text_node, 'html')
    text
  end

  def traverse(e, mode='html')
    r = ''
    e.children.each { |c| 
      s = handle_node(c, mode)
      r << s
    }
    r
  end
  
  def write_juan(juan_no, body)
    if @sutra_no.match(/^(T05|T06|T07)n0220/)
      work = "T0220"
    else
      work = @sutra_no.sub(/^([A-Z]{1,2})\d{2,3}n(.*)$/, '\1\2')
    end

    back = html_back(juan_no)

    # 如果是卷跨冊的上半部
    if juan_cross_vol(@vol, @work_id, juan_no) == 1
      @html_buf = body
      @back_buf = back
      return
    end

    unless @html_buf.blank?
      body = @html_buf + body
      @html_buf = ''
    end

    unless @back_buf.blank?
      back = @back_buf + back
      @back_buf = ''
    end

    unless back.empty?
      back = "<hr><h1>校注</h1>\n" + back
    end

    data = {
      title: @title,
      body: body,
      back: back,
      copyright: html_copyright(work, juan_no)
    }
    template_fn = Rails.root.join('lib', 'tasks', 'x2h_for_download.html')
    template = File.read(template_fn)
    html = template % data
    
    fn = "#{work}_%03d.html" % juan_no
    output_path = File.join(@out_folder, fn)
    File.write(output_path, html)
  end
  
  def zip_by_work(canon)
    folder = File.join(@out_root, @series)
    Dir.entries(folder).each do |work|
      next if work.start_with? '.'
      juan_folder = File.join(folder, work)
      zipfile_name = File.join(@out_root, "#{work}.html.zip")
      $stderr.puts zipfile_name
      Zip::File.open(zipfile_name, Zip::File::CREATE) do |zipfile|
        Dir.entries(juan_folder).sort.each do |filename|
          next if filename.start_with? '.'
          # Two arguments:
          # - The name of the file as it will appear in the archive
          # - The original file, including the path to find it
          zipfile.add(filename, File.join(juan_folder, filename))
        end
      end
      FileUtils.mv Dir.glob("#{juan_folder}/*.html"), @out_root
      FileUtils.rm_rf juan_folder
    end
    FileUtils.rm_rf folder
  end

  include P5aToHtmlShare
  include CbetaP5aShare
end
