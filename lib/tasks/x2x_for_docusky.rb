require 'cgi'
require 'date'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'set'
require_relative 'html-node'
require_relative 'x2h_share'
require_relative 'cbeta_p5a_share'
require_relative 'share'

# Convert CBETA XML P5a to HTML
#
# CBETA XML P5a 可由此取得: https://github.com/cbeta-git/xml-p5a
#
# 轉檔規則請參考: http://wiki.ddbc.edu.tw/pages/CBETA_XML_P5a_轉_HTML
class P5aToDocusky
  # 內容不輸出的元素
  PASS=['anchor', 'back', 'foreign', 'graphic', 'mulu', 'teiHeader']

  # 某版用字缺的符號
  MISSING = '－'
  
  private_constant :PASS, :MISSING

  # @param xml_root [String] 來源 CBETA XML P5a 路徑
  # @param out_root [String] 輸出 HTML 路徑
  def initialize(xml_root, out_root)
    @xml_root = xml_root
    @out_root = out_root
    @cbeta = CBETA.new
    @gaijis = MyCbetaShare.get_cbeta_gaiji
    @gaijis_skt = MyCbetaShare.get_cbeta_gaiji_skt
    @us = UnicodeService.new
    
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
    return convert_all if target.nil?

    arg = target.upcase
    if arg.size <= 2
      handle_collection(arg)
    else
      abort "輸出檔以經為單位，必須整部藏經一起"
    end
  end

  private
  
  def convert_all
    each_canon(@xml_root) do |c|
      handle_collection(c)
    end
  end

  def e_byline(e)
    r = '<Paragraph Type="byline">'
    r += traverse(e)
    r + "</Paragraph>\n"
  end

  def e_cell(e)
    cell = HtmlNode.new('div')
    cell['Type'] = 'table-cell'
    cell['rowspan'] = e['rows'] if e.key? 'rows'
    cell['colspan'] = e['cols'] if e.key? 'cols'
    cell.content = traverse(e)
    cell.to_s + "\n"
  end

  def e_div(e)
    if e.has_attribute? 'type'
      @open_divs << e
      r = traverse(e)
      @open_divs.pop
      return %(<div Type="#{e['type']}">#{r}</div>\n)
    else
      return traverse(e)
    end
  end

  def e_g(e, mode)
    gid = e['ref'][1..-1]

    if gid.start_with? 'CB'
      g = @gaijis[gid]
    else
      g = @gaijis_skt[gid]
    end

    abort "Line:#{__LINE__} 無缺字資料:#{gid}" if g.nil?
    
    if gid.start_with?('SD')
      return g['symbol'] if g.key? 'symbol'
      return g['romanized'] unless g['romanized'].blank?
      return "[#{gid}]"
    end
    
    if gid.start_with?('RJ')
      return g['romanized'] unless g['romanized'].blank?
      return "[#{gid}]"
    end
   
    return g['uni_char'] if @us.level2?(g['unicode']) # 直接採用 unicode

    default = ''
    if @gaiji_norm.last # 如果沒有特別指定不用通用字
      return g['norm_uni_char'] if @us.level2?(g['norm_unicode'])
      return g['norm_big5_char'] if g.key?('norm_big5_char')
    end

    abort "#{gid} 缺組字式" if g['composition'].empty?
    
    g['composition']
  end

  def e_head(e)
    r = ''
    unless e['type'] == 'added'
      i = @open_divs.size
      r = %(<Paragraph type="head">%s</Paragraph>\n) % traverse(e)
    end
    r
  end

  def e_item(e)
    s = traverse(e)
    
    # ex: T18n0850_p0087a14
    if e.key? 'n'
      s = e['n'] + s
    end
    
    %(<div Type="list-item">#{s}</div>\n)
  end

  def e_juan(e)
    %(<Paragraph Type="juan">%s</Paragraph>\n) % traverse(e)
  end

  def e_l(e)
    if @lg_type == 'abnormal'
      return traverse(e)
    end

    @in_l = true

    cell = HtmlNode.new('div')
    cell['class'] = 'lg-cell'
    cell.content = traverse(e)
    
    @first_l = false
    
    r = cell.to_s
    
    unless @lg_row_open
      r = "\n<div Type='lg-row'>" + r
      @lg_row_open = true
    end
    @in_l = false
    r
  end

  def e_lb(e)
    # 卍續藏有 X 跟 R 兩種 lb, 只處理 X
    return '' if e['ed'] != @series

    @lb = e['n']
    
    r = ''
    if @lg_row_open && !@in_l
      # 每行偈頌放在一個 lg-row 裡面
      # T46n1937, p. 914a01, l 包雙行夾註跨行
      # T20n1092, 337c16, lb 在 l 中間，不結束 lg-row
      r += "</div>\n"
      @lg_row_open = false
    end
    unless @next_line_buf.empty?
      r += @next_line_buf
      @next_line_buf = ''
    end
    
    r + %(<Lb Key="#{@lb}"/>)
  end

  def e_lg(e)
    r = ''
    @lg_type = e['type']
    if @lg_type == 'abnormal'
      r = "<Paragraph Type='lg-abnormal'>" + traverse(e) + "</Paragraph>\n"
    else
      @first_l = true
      node = HtmlNode.new('div')
      node['Type'] = 'lg'
      @lg_row_open = false
      node.content = traverse(e)
      if @lg_row_open
        node.content += '</div>'
        @lg_row_open = false
      end
      r = "\n" + node.to_s
    end
    r
  end

  def e_list(e)
    %(<div Type="list">%s</div>) % traverse(e)
  end

  def e_milestone(e)
    r = ''
    if e['unit'] == 'juan'
      r += "</div>" * @open_divs.size  # 如果有 div 跨卷，要先結束, ex: T55n2154, p. 680a29, 跨 19, 20 兩卷
      @juan = e['n'].to_i
      r += "<juan #{@juan}>"
      @open_divs.each { |d|
        r += %(<div Type="#{d['type']}">)
      }
    end
    r
  end

  def e_note(e)
    n = e['n']
    if e.has_attribute?('type')
      t = e['type']
      case t
      when 'equivalent', 'orig', 'mod', 'rest', 'star'
        return ''
      else
        return '' if t.start_with?('cf')
      end
    end

    if e.has_attribute?('resp')
      return '' if e['resp'].start_with? 'CBETA'
    end

    r = traverse(e)
    if e.has_attribute?('place')
      if %w[inline inline2].include?(e['place'])
        r = %(<Udef_Class Type="doube-line-note">#{r}</Udef_Class>)
      elsif e['place']=='interlinear'
        r = %(<Udef_Class Type="interlinear-note">#{r}</Udef_Class>)
      end
    end
    r
  end
  
  def e_p(e)
    if e.key? 'type'
      r = %(<Paragraph Type="%s">) % e['type']
    else
      r = '<Paragraph>'
    end
    r += traverse(e)
    r + "</Paragraph>\n"
  end
  
  def e_pb(e)
    return '' unless e.key? 'n'
    %(<Pb Key="#{e['n']}"/>)
  end

  def e_reg(e)
    r = ''
    choice = e.at_xpath('ancestor::choice')
    r = traverse(e) if choice.nil?
    r
  end
  
  def e_row(e)
    '<div Type="table-row">' + traverse(e) + "</div>\n"
  end

  def e_sg(e)
    '(' + traverse(e) + ')'
  end
  
  def e_t(e)
    if e.has_attribute? 'place'
      return '' if e['place'].include? 'foot'
    end
    r = traverse(e)

    # 不是 悉漢雙行對照
    tt = e.at_xpath('ancestor::tt')
    unless tt.nil?
      return r if %w(app single-line).include? tt['type']
      return r if tt['place'] == 'inline'
      return r if tt['rend'] == 'normal'
    end

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
    "<div Type='table'>" + traverse(e) + "</div>\n"
  end
  
  def e_unclear(e)
    ele_unclear(e)
  end
  
  def handle_collection(c)
    $stderr.puts "handle_collection: #{c}"
    @series = c
    @works_info = read_info_by_canon(c)
    @work_docs = ''
    @work_id = nil
    @work_metadata = {}
    @work_metadata2 = {}
    
    folder = File.join(@xml_root, @series)
    
    Dir.each_child(folder).sort.each do |vol|
      next if vol.start_with? '.'
      handle_vol(vol)
    end
    write_work(@work_id, 'xxx')
    puts
  end

  def handle_node(e, mode)
    return '' if e.comment?
    return handle_text(e, mode) if e.text?
    return '' if PASS.include?(e.name)

    r = case e.name
    when 'anchor'    then e_anchor(e)
    when 'byline'    then e_byline(e)
    when 'cell'      then e_cell(e)
    when 'div'       then e_div(e)
    when 'g'         then e_g(e, mode)
    when 'head'      then e_head(e)
    when 'item'      then e_item(e)
    when 'juan'      then e_juan(e)
    when 'l'         then e_l(e)
    when 'lb'        then e_lb(e)
    when 'lg'        then e_lg(e)
    when 'list'      then e_list(e)
    when 'note'      then e_note(e)
    when 'milestone' then e_milestone(e)
    when 'p'         then e_p(e)
    when 'pb'        then e_pb(e)
    when 'rdg'       then ''
    when 'reg'       then e_reg(e)
    when 'row'       then e_row(e)
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
    @dila_note = 0
    @gaiji_norm = [true]
    @in_l = false
    @juan = 0
    @lg_row_open = false
    @mod_notes = Set.new
    @next_line_buf = ''
    @open_divs = []
    @sutra_no = File.basename(xml_fn, ".xml")
    
    old_work_id = @work_id
    @work_id = CBETA.get_work_id_from_file_basename(@sutra_no)
    write_work(old_work_id, @work_id)
    
    if @sutra_no.match(/^(T05|T06|T07)n0220/)
      @sutra_no = "#{$1}n0220"
    end    
    
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
    print vol + ' '
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
    puts "convert volumns: #{v1}..#{v2}"
    @series = CBETA.get_canon_from_vol(v1)
    folder = File.join(@xml_root, @series)
    Dir.foreach(folder) { |vol|
      next if vol < v1
      next if vol > v2
      handle_vol(vol)
    }
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

  def read_mod_notes(doc)
    doc.xpath("//note[@type='mod']").each { |e|
      n = e['n']
      @mod_notes << n
      
      # 例 T01n0026_p0506b07, 原註標為 7, CBETA 修訂為 7a, 7b
      n.match(/[a-z]$/) {
        @mod_notes << n[0..-2]
      }
    }
  end

  def parse_xml(xml_fn)
    @pass = [false]

    doc = open_xml(xml_fn)
    
    e = doc.at_xpath("//titleStmt/title")
    @title = traverse(e, 'txt')
    @title = @title.split()[-1]
    @title.sub!(/^(.*)\(.*?\)$/, '\1')    
    
    e = doc.at_xpath("//projectDesc/p[@lang='zh-Hant']")
    abort "找不到貢獻者" if e.nil?
    @contributors = e.text
    
    set_work_metadata
    read_mod_notes(doc)

    root = doc.root()
    text_node = root.at_xpath("text")
    @pass = [true]

    text = handle_node(text_node, 'html')
    text
  end
  
  def read_info_by_canon(canon)
    fn = File.join(Rails.configuration.x.work_info, "#{canon}.json")
    JSON.load_file(fn)
  end
    
  def set_work_metadata
    return if @work_metadata.key? @work_id
    puts "work_id: #{@work_id}"
    info = @works_info[@work_id]
    abort __LINE__ if info.nil?

    xml = "<corpus>%s</corpus>\n"
    xml << "<docclass>#{@work_id}</docclass>\n"
    xml << "<title>#{@title}</title>\n"
    xml << "<doctype>#{info['category']}</doctype>\n"
    
    xml2 = "<xml_metadata>\n"
    xml2 << "\t<TextNo>#{@work_id}</TextNo>\n"
    xml2 << "\t<TextTitle>#{@title}</TextTitle>\n"
    xml2 << "\t<Catgeory>#{info['category']}</Catgeory>\n"
    
    if info.key?('contributors')
      a = info['contributors'].map do |x|
        s = x['name']
        s << "(#{x['id']})" if x.key?('id')
      end
      creators = a.join(';')
      xml  << "<author>#{creators}</author>\n"
      xml2 << "\t<Author>#{creators}</Author>\n"
    end
    
    if info.key?('places')
      a = info['places'].map do |x|
        s = x['name']
        s << "(#{x['id']})" if x.key?('id')
      end
      places = a.join(',')
      xml  << "<geo>#{places}</geo>\n"
      xml2 << "\t<Place>#{places}</Place>\n"
    end
    
    if i = info['time_from']
      xml  << "<date_not_before>#{i}</date_not_before>\n"
      xml2 << "\t<DateNotBefore>#{i}</DateNotBefore>\n"
    end

    if i = info['time_to']
      xml  << "<date_not_after>#{i}</date_not_after>\n"
      xml2 << "\t<DateNotAfter>#{i}</DateNotAfter>\n"
    end

    if s = info['dynasty']
      xml  << "<time_dynasty>#{s}</time_dynasty>\n"
      xml2 << "\t<Dynasty>#{s}</Dynasty>\n"
    end

    xml2 << "</xml_metadata>\n"
    
    @work_metadata[@work_id]  = xml
    @work_metadata2[@work_id] = xml2
  end
  
  def traverse(e, mode='html')
    r = ''
    e.children.each { |c| 
      s = handle_node(c, mode)
      r += s
    }
    r
  end  
  
  def write_juan(juan_no, body)
    basename = "#{@work_id}_%03d" % juan_no
    
    s = %(<document filename="#{basename}">\n)
    s += @work_metadata[@work_id] % basename
    s += "<doc_content>\n"
    s += %(<div Type="body">\n)
    s += body
    s += "</div>\n"
    s += "</doc_content>\n"
    s += @work_metadata2[@work_id]
    s += "</document>\n"
    
    # 把本卷的 xml 累加到全經的 xml
    @work_docs += s
    
    fn = basename + ".docusky.xml"
    output_path = File.join(@out_root, fn)
    write_xml(output_path, s)
  end
  
  def write_work(old_work_id, new_work_id)
    return if old_work_id.nil?
    return if old_work_id == new_work_id
    fn = File.join(@out_root, "#{old_work_id}.docusky.xml")
    write_xml(fn, @work_docs)
    @work_docs = ''
  end
  
  def write_xml(fn, xml)
    s = %(<?xml version="1.0"?>
<ThdlPrototypeExport>
<documents>
#{xml}</documents>
</ThdlPrototypeExport>)
    File.write(fn, s)
  end
  
  include CbetaP5aShare
end
