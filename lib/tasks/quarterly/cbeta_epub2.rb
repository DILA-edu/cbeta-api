require 'rubygems'
require 'cgi'
require 'colorize'
require 'date'
require 'erb'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'set'
require 'pp'
require 'tmpdir'
require 'cbeta'
require_relative 'html-node'

# Convert CBETA XML P5a to EPUB2
#
# CBETA XML P5a 可由此取得: https://github.com/cbeta-git/xml-p5a
class CbetaEpub
  # 內容不輸出的元素
  PASS=['back', 'figDesc', 'teiHeader']

  # 某版用字缺的符號
  MISSING = '－'
  
  SCRIPT_FOLDER = File.dirname(__FILE__)
  MAIN = 'main.xhtml'
  
  private_constant :PASS, :MISSING, :SCRIPT_FOLDER, :MAIN

  # @param temp_folder [String] 供 EPUB 暫存工作檔案的路徑
  # @option opts [String] :front_page 內文前可以加一份 HTML 檔，例如「編輯說明」
  # @option opts [String] :front_page_title 加在目錄的 front_page 標題
  # @option opts [String] :back_page 內文後可以加一份 HTML 檔，例如「版權聲明」
  # @option opts [String] :back_page_title 加在目錄的 back_page 標題
  # @option opts [Boolean] :juan_toc 目次中是否要有卷目次，預設為 true
  #
  # @example
  #   options = {
  #     front_page: '/path/to/front_page.xhtml',
  #     front_page_title: '編輯說明',
  #     back_page: '/path/to/back_page.xhtml',
  #     back_page_title: '贊助資訊',
  #   }
  #   c = CBETA::P5aToEPUB.new('/path/to/temp/working/folder', options)
  #   c.convert_folder('/path/to/xml/roo', '/path/for/output/epubs')  
  def initialize(opts={})
    @settings = {
      juan_toc: true
    }
    @settings.merge!(opts)
    @cbeta = CBETA.new
    @gaijis = CBETA::Gaiji.new(@settings[:gaiji_base])
    
    @us = UnicodeService.new
    @ncx_template = File.read(File.join(@settings[:template], 'toc.ncx.erb'))
  end

  # 將某個 xml 轉為一個 EPUB
  # @param input_path [String] 輸入 XML 檔路徑
  # @param output_paath [String] 輸出 EPUB 檔路徑
  def convert_file(input_path, output_path)
    return false unless input_path.end_with? '.xml'
      
    Dir.mktmpdir 'cbeta-epub2' do |dir|
      @temp_folder = dir
      @book_id = File.basename(input_path, ".xml")    
      sutra_init
      handle_file(input_path)
      create_epub(output_path)
    end
  end

  # 將某個資料夾下的每部作品都轉為一個對應的 EPUB。
  # 跨冊的作品也會合成一個 EPUB。
  #
  # @example
  #   require 'cbeta'
  #   
  #   IMG = '/Users/ray/Documents/Projects/D道安/figures'
  #   
  #   c = CBETA::P5aToEPUB.new(IMG)
  #   c.convert_folder('/Users/ray/Documents/Projects/D道安/xml-p5a/DA', '/temp/cbeta-epub/DA')
  def convert_folder(input_folder, output_folder)
    puts "convert folder: #{input_folder} to #{output_folder}"
    @todo = {}
    
    # 先檢視整個資料夾，哪些是要多檔合一
    prepare_todo_list(input_folder, output_folder)
    
    @todo.keys.sort.each do |k|
      v = @todo[k]
      convert_sutra(k, v[:xml_files], v[:epub])
    end
  end
  
  # 將多個 xml 檔案合成一個 EPUB
  #
  # @example 大般若經 跨三冊 合成一個 EPUB
  #   require 'cbeta'
  #   
  #   xml_files = [
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/05/T05n0220a.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/06/T06n0220b.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220c.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220d.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220e.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220f.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220g.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220h.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220i.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220j.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220k.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220l.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220m.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220n.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220o.xml',
  #   ]
  #   
  #   c = CBETA::P5aToEPUB.new
  #   c.convert_sutra('T0220', xml_files, '/temp/cbeta-epub/T0220.epub')
  def convert_sutra(book_id, xml_files, out)
    puts '-' * 10
    puts "convert_sutra, book_id: #{book_id}"
    Dir.mktmpdir 'cbeta-epub2' do |dir|
      @temp_folder = dir
      @book_id = book_id
      sutra_init
      xml_files.sort.each { |f| handle_file(f) }
    
      if xml_files.size > 1
        @title.sub!(/^(.*)\(.*?\)$/, '\1')
        @title.sub!(/^(.*?)(（.*?）)+$/, '\1')
      end
      create_epub(out)
    end
  end

  private
  
  def add_image(fn)
    @image_count += 1
    href = File.join('images', fn)
    
    type = case File.extname(fn)
    when '.gif' then 'image/gif'
    when '.jpg' then 'image/jpeg'
    when '.png' then 'image/png'
    when '.svg' then 'image/svg+xml'
    else
      puts "Error: 不明圖檔類型: #{fn}"
      abort "cbeta_epub2.rb 行號: #{__LINE__}"
    end
    @manifest += %[<item id="image#{@image_count}" href="#{href}" media-type="#{type}"/>\n]
  end
  
  def add_xhtml(id, href)
    @manifest += %[<item id="#{id}" href="#{href}" media-type="application/xhtml+xml"/>\n]
    @spin += %[<itemref idref="#{id}"/>\n]
  end
    
  def copy_oebps_file(src, dest)
    dest = File.join(@temp_folder, 'OEBPS', dest)
    FileUtils.copy(src, dest)
  end

  def write_text_to_oebps_file(text, dest)
    dest = File.join(@temp_folder, 'OEBPS', dest)
    File.write(dest, text)
  end
  
  def create_epub(output_path)
    @epub_uid = "http://www.cbeta.org/epub2/#{@book_id}"
    prepare_mimetype
    prepare_meta_inf
    prepare_oebps
    create_toc
    prepare_cover    
    zip_epub output_path
    puts "output: #{output_path}\n"
  end

  def create_html_by_juan
    juans = @main_text.split(/(<juan \d+>)/)
    open = false
    fo = nil
    juan_no = nil
    fn = ''
    buf = ''
    # 一卷一檔
    juans.each do |j|
      if j =~ /<juan (\d+)>$/
        juan_no = $1.to_i
        fn = "%03d.xhtml" % juan_no
        add_xhtml("juan#{juan_no}", "juans/#{fn}")
        output_path = File.join(@temp_folder, 'OEBPS', 'juans', fn)
        fo = File.open(output_path, 'w')
        open = true
        s = <<eos
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  <title>#{@title}</title>
  <link rel="stylesheet" type="text/css" href="../cbeta.css" />
</head>
<body>
<div id='body'>
eos
        fo.write(s)
        fo.write(buf)
        buf = ''
      elsif open
        fo.write(j + "\n</div><!-- end of div[@id='body'] -->\n")
        fo.write('</body></html>')
        fo.close
      else
        buf = j
      end
    end
  end
  
  def create_toc
    if @settings[:juan_toc]
      nav_point = new_nav_point '卷目次', 'juans/001.xhtml#body'
      @toc_root.add_child nav_point
      juan_nav = nav_point
      @toc_juan.each do |juan|
        nav_point = new_nav_point juan[:label], juan[:href]
        juan_nav.add_child nav_point
      end
    end
    
    if @settings[:back_page_title]
      label = @settings[:back_page_title]
      nav_point = new_nav_point label, 'back.xhtml'
      @toc_root.add_child nav_point
    end
    
    @nav_map = @toc_root.to_xml(encoding: 'UTF-8', indent: 2)
        
    renderer = ERB.new(@ncx_template)
    output = renderer.result(binding)

    fn = File.join(@temp_folder, 'OEBPS', 'toc.ncx')
    File.write(fn, output)
    
    create_toc_html
  end
  
  def create_toc_html
    r = '<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <title>目次</title>
  <link type="text/css" rel="stylesheet" href="cbeta.css" />
</head>
<body>
    <h1>目次</h1>
    <div>'
    r += create_toc_html_traverse(@toc_root)
    r += "</div></body></html>"
    fn = File.join(@temp_folder, 'OEBPS', 'toc.xhtml')
    File.write(fn, r)
  end
  
  def create_toc_html_traverse(parent)
    r = ''
    parent.children.each do |c|
      next unless c.name == 'navPoint'
      content = c.at_xpath('navLabel/text').text
      href = c.at_xpath('content')['src']
      r += %(<li><a href='#{href}'>#{content}</a>\n)
      r += create_toc_html_traverse(c)
      r += "</li>\n"
    end
    unless r.empty?
      r = "<ul>\n#{r}</ul>"
    end
    r
  end
  
  def e_anchor(e)
    if e.has_attribute?('type')
      if e['type'] == 'circle'
        return '◎'
      end
    end

    ''
  end

  def e_app(e)
    traverse(e)
  end

  def e_byline(e)
    r = '<p class="byline">'
    r += traverse(e)
    r + '</p>'
  end

  def e_cell(e)
    doc = Nokogiri::XML::Document.new
    cell = doc.create_element('td')
    cell['rowspan'] = e['rows'] if e.key? 'rows'
    cell['colspan'] = e['cols'] if e.key? 'cols'
    cell.inner_html = traverse(e)
    to_html(cell) + "\n"
  end

  def e_corr(e)
    "<span class='corr'>" + traverse(e) + "</span>"
  end

  def e_div(e)
    if e.has_attribute? 'type'
      @open_divs << e
      r = traverse(e)
      @open_divs.pop
      return "\n<div class='div-#{e['type']}'>#{r}</div>"
    else
      return traverse(e)
    end
  end

  # figure 可能包在 p 裡面, 例如 Y01n0001_p0046a05
  def e_figure(e)
    traverse(e)
  end
  
  def e_foreign(e)
    if e.key?('place') and e['place'].include?('foot')
      return ''
    end
    traverse(e)
  end

  def e_g(e, mode)
    gid = e['ref'][1..-1]
    g = @gaijis[gid]
    abort "Line:#{__LINE__} 無缺字資料:#{gid}".red if g.nil?

    if gid.start_with?('SD')
      c = g['symbol']
      return c unless c.nil?

      c = g['romanized']
      return c unless c.nil?

      if mode == 'txt'
        puts "警告：純文字模式出現悉曇字：#{gid}"
        return gid
      else
        # 如果沒有羅馬轉寫就顯示圖檔
        src = File.join(@settings[:sd_gif], gid[3..4], gid+'.gif')
        basename = File.basename(src)
        copy_oebps_file(src, "images/#{basename}")
        add_image(basename)
        return "<img src='../images/#{basename}' />"
      end
    end
    
    if gid.start_with?('RJ')
      c = g['symbol']
      return c unless c.nil?

      c = g['romanized']
      return c unless c.nil?
      
      if mode == 'txt'
        puts "警告：純文字模式出現蘭札體：#{gid}"
        return gid
      else
        # 如果沒有羅馬轉寫就顯示圖檔
        src = File.join(@settings[:rj_gif], gid[3..4], gid+'.gif')
        basename = File.basename(src)
        copy_oebps_file(src, "images/#{basename}")
        add_image(basename)
        return "<img src='../images/#{basename}' />"
      end
    end

    normal_or_zzs(gid)
  end

  def e_graphic(e)
    url = e['url']
    url.sub!(/^.*figures\/(.*)$/, '\1')
    
    src = File.join(@settings[:figures], url)
    basename = File.basename(src)
    copy_oebps_file(src, "images/#{basename}")    
    add_image(basename)
    
    "<img src='../images/#{basename}' alt='#{basename}' />"
  end

  def e_head(e)
    r = ''
    unless e['type'] == 'added'
      i = @open_divs.size
      r = "\n<p class='h#{i}'>%s</p>" % traverse(e)
    end
    r
  end

  def e_item(e)
    "\n<li>%s</li>\n" % traverse(e)
  end

  def e_juan(e)
    "\n<p class='juan'>%s</p>" % traverse(e)
  end

  # 2018-07-16 email maha:
  # 偈頌方面，限於手機寬度，可以讓文字自動折行，但句子與句子之間要有空格。
  def e_l(e)
    s = traverse(e)
    "<div class='lg-row'>#{s}</div>\n"
  end

  def e_lb(e)
    # 卍續藏有 X 跟 R 兩種 lb, 只處理 X
    return '' if e['ed'] != @canon
    
    # 佛寺志的偈頌遇 lb 都不換行
    return '' if @canon=='GA' or @canon=='GB'

    @lb = e['n']
    r = ''

    #if e.parent.name == 'lg' and $lg_row_open
    if @lg_row_open && !@in_l
      # 每行偈頌放在一個 lg-row 裡面
      # T46n1937, p. 914a01, l 包雙行夾註跨行
      # T20n1092, 337c16, lb 在 l 中間，不結束 lg-row
      r += "</div><!-- end of lg-row -->"
      @lg_row_open = false
    end

    # <p type="pre">
    if @p_type == 'pre'
      r += "<br/>"
    end

    unless @next_line_buf.empty?
      r += @next_line_buf
      @next_line_buf = ''
    end
    r
  end

  def e_lem(e)
    r = ''
    w = e['wit']
    if w.include? '【CB】' and not w.include? @orig
      r = "<span class='corr'>%s</span>" % traverse(e)
    else
      r = traverse(e)
    end
    r
  end

  def e_lg(e)
    r = ''
    @lg_type = e['type']

    if @lg_type != 'regular'
      node = HtmlNode.new('p')
      node.content = traverse(e)
      node['style'] = e['style'] if e.key? 'style'
      classes = ['lg-abnormal']
      classes << e['rend'] if e.key? 'rend'
      node['class'] = classes.join(' ')
      return node.to_s
    end

    @first_l = true
    node = HtmlNode.new('div')

    classes = ['lg']
    classes << e['rend'] if e.key? 'rend'
    classes << e['type'] if e.key? 'type'
    node['class'] = classes.join(' ')

    if e.key?('style')
      node['style'] = e['style'].gsub(/text-indent:[^:]*/, '')
    end

    node.content = traverse(e)
    "\n" + node.to_s
  end

  def e_list(e)
    doc = Nokogiri::XML::Document.new
    node = doc.create_element('ul')
    node.inner_html = traverse(e)

    classes = []
    if e.key? 'rendition'
      classes << e['rendition']
    end

    if e.key? 'rend'
      classes << e['rend']
    end

    node['class'] = classes.join(' ')

    "\n" + to_html(node)
  end

  def e_milestone(e)
    r = ''
    if e['unit'] == 'juan'
      r += "</div>" * @open_divs.size  # 如果有 div 跨卷，要先結束, ex: T55n2154, p. 680a29, 跨 19, 20 兩卷
      @juan += 1
      r += "<juan #{@juan}>"
      @open_divs.each { |d|
        r += "<div class='#{d['type']}'>"
      }
    end
    r
  end

  def e_mulu(e)
    @mulu_count += 1
    fn = "juans/%03d.xhtml" % @juan
    if e['type'] == '卷'
      if @settings[:juan_toc]
        @toc_juan << {
          label: e['n'],
          href: "#{fn}#mulu#{@mulu_count}"
        }
      end
    else
      level = e['level'].to_i
      while @current_nav.size > (level+1)
        @current_nav.pop
      end
      
      @depth = level if level > @depth
    
      label = traverse(e, 'txt')
      href = "#{fn}#mulu#{@mulu_count}"
      nav_point = new_nav_point label, href
      @current_nav.last.add_child nav_point
      @current_nav << nav_point
    end
    "<a id='mulu#{@mulu_count}' />"
  end

  def e_note(e)
    n = e['n']
    if e.has_attribute?('type')
      t = e['type']
      case t
      when 'add', 'equivalent', 'orig', 'orig_biao', 'orig_ke', 'mod', 'rest'
        return ''
      else
        return '' if t.start_with?('cf')
      end
    end

    if e.has_attribute?('resp')
      return '' if e['resp'].start_with? 'CBETA'
    end

    if e.has_attribute?('place') && e['place']=='inline'
      r = traverse(e)
      return "<span class='note-inline'>(#{r})</span>"
    else
      return traverse(e)
    end
  end

  def e_p(e)
    @p_type = e['type']
    content = traverse(e)
    @p_type = nil

    if e.at_xpath('figure')
      node = HtmlNode.new('div')
    else
      node = HtmlNode.new('p')
    end
    
    classes = []
    classes << e['type'] if e.key? 'type'

    # p 的 rend 屬性可能有空格隔開的多值
    classes += e['rend'].split if e.key? 'rend'
    node['class'] = classes.join(' ') unless classes.empty?

    node['style'] = e['style'] if e.key? 'style'
    
    node.content = content
    node.to_s + "\n"
  end

  def e_row(e)
    "\n<tr>" + traverse(e) + "</tr>"
  end

  def e_seg(e)
    node = HtmlNode.new('span')
    if e.key? 'rend'
      node['class'] = e['rend']
    end
    node.content = traverse(e)
    node.to_s
  end

  def e_sg(e)
    '(' + traverse(e) + ')'
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
    "\n<table>" + traverse(e) + "</table>"
  end
  
  def handle_node(e, mode)
    return '' if e.comment?
    return handle_text(e, mode) if e.text?
    return '' if PASS.include?(e.name)
    
    nor_flag = true
    if @nor_flag.last
      nor_flag = false if e['rend'] == 'no_nor'
    else
      nor_flag = false
    end
    @nor_flag << nor_flag

    r = case e.name
    when 'anchor'    then e_anchor(e)
    when 'app'       then e_app(e)
    when 'byline'    then e_byline(e)
    when 'caesura'   then '　'
    when 'cell'      then e_cell(e)
    when 'corr'      then e_corr(e)
    when 'div'       then e_div(e)
    when 'figure'    then e_figure(e)
    when 'foreign'   then e_foreign(e)
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
    when 'rdg'       then ''
    when 'reg'       then ''
    when 'row'       then e_row(e)
    when 'seg'       then e_seg(e)
    when 'sic'       then ''
    when 'sg'        then e_sg(e)
    when 't'         then e_t(e)
    when 'table'     then e_table(e)
    when 'tt'        then e_tt(e)
    else traverse(e)
    end
    @nor_flag.pop
    r
  end


  def handle_file(xml_fn)
    return unless xml_fn.end_with? '.xml'
    puts "read #{xml_fn}"
    @in_l = false
    @lg_row_open = false
    @mod_notes = Set.new
    @next_line_buf = ''
    @open_divs = []
    
    canon = @book_id[0, 2]
    case canon
    when 'DA'
      @orig = nil
    when 'HM'
      @orig = '【惠敏】'
    else
      canon = CBETA.get_canon_id_from_work_id(@book_id)
      @orig = @cbeta.get_canon_abbr(canon)
      abort "未處理底本: #{canon}" if @orig.nil?
    end

    text = parse_xml(xml_fn)

    # 註標移到 lg-cell 裡面，不然以 table 呈現 lg 會有問題
    text.gsub!(/(<a class='noteAnchor'[^>]*><\/a>)(<div class="lg-cell"[^>]*>)/, '\2\1')
    
    @main_text += text    
  end


  def handle_text(e, mode)
    s = e.content().chomp
    return '' if s.empty?
    return '' if e.parent.name == 'app'

    # cbeta xml 文字之間會有多餘的換行
    s.gsub!(/[\n\r]/, '')

    # xml p5a 裡面會直接採用 unicode
    # 例如：B01n0001, p. 71a03, 「將𥸩此文」的「𥸩」（經查該字為 extension-b 字元 U+25E29）
    # 所以要逐字檢查是否在 Unicode 2.0 範圍裡
    r = ''
    s.each_char do |c|
      if @us.level1?(c)
        r += c
      else
        cb = @gaijis.unicode_to_cb(c)
        abort("Unicode 字元 #{c} 在缺字資料中找不到") if cb.nil?
        r += normal_or_zzs(cb)
      end
    end
    
    # 把 & 轉為 &amp;
    CGI.escapeHTML(r)
  end

  def lem_note_cf(e)
    # ex: T32n1670A.xml, p. 703a16
    # <note type="cf1">K30n1002_p0257a01-a23</note>
    refs = []
    e.xpath('./note').each { |n|
      if n.key?('type') and n['type'].start_with? 'cf'
        refs << n.content
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
  
  def new_nav_point(label, src=nil)
    @play_order += 1
    nav_point = @toc_doc.create_element 'navPoint', id: "navpoint-#{@play_order}", playOrder: @play_order
    nav_point.add_child("<navLabel><text>#{label}</text></navLabel>")
    nav_point.add_child("<content src='#{src}'/>")
    nav_point
  end
  
  def normal_or_zzs(cb)
    g = @gaijis[cb]
    
    # 通用字 比 組字式 優先，如果沒有指定 no_nor 的話
    if @nor_flag.last
      return g['uni_char'] if @us.level1?(g['unicode'])
      return g['norm_uni_char'] if @us.level1?(g['norm_unicode'])
      return g['norm_big5_char'] if g.key?('norm_big5_char')
    end

    abort "#{cb} 缺組字式" unless g.key? 'composition'
    
    g['composition']
  end
  
  def sutra_init
    @canon = @book_id[0, 2]
    unless @canon == 'HM'
      @canon = CBETA.get_canon_id_from_work_id(@book_id)
    end
    
    @depth = 0
    @play_order = 0
    
    @toc_doc = Nokogiri::XML('<navMap></navMap>',&:noblanks)
    @toc_doc.remove_namespaces!()
    @toc_root = @toc_doc.root
    @current_nav = [@toc_root]
    
    if @settings[:front_page_title]
      nav_point = new_nav_point '編輯說明', 'front.xhtml'
      @toc_root.add_child nav_point
    end
    
    nav_point = new_nav_point '章節目次', 'juans/001.xhtml'
    @toc_root.add_child nav_point
    @current_nav << nav_point
    
    @image_count = 0
    @mulu_count = 0
    @main_text = ''
    @manifest = ''
    @nor_flag = [true]
    @dila_note = 0
    @spin = ''
    @toc_juan = [] # 卷目次
    @juan = 0
    
    FileUtils::mkdir_p File.join(@temp_folder, 'OEBPS', 'images')
    FileUtils::mkdir_p File.join(@temp_folder, 'OEBPS', 'juans')
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
    
    node = doc.at_xpath("//titleStmt/author")
    @author = node.nil? ? '' : node.text
    
    read_mod_notes(doc)

    root = doc.root()
    body = root.xpath("text/body")[0]
    @pass = [true]

    text = traverse(body)
    text
  end
  
  def prepare_cover
    cover = File.join(@settings[:covers], @canon, "#{@book_id}.jpg")
    if File.exist? cover
      copy_oebps_file(cover, "images/cover.jpg")
    else
      puts "no cover #{cover}"
    end
  end
  
  def prepare_meta_inf
    folder = File.join(@temp_folder, 'META-INF')
    Dir.mkdir(folder)
    fn = File.join(folder, 'container.xml')
    s = '<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf"
     media-type="application/oebps-package+xml" />
  </rootfiles>
</container>'
    File.write(fn, s)
  end
  
  def prepare_mimetype
    fn = File.join(@temp_folder, 'mimetype')
    File.write(fn, 'application/epub+zip')
  end
  
  def prepare_oebps
    folder = File.join(@temp_folder, 'OEBPS')
    Dir.mkdir(folder) unless Dir.exist? folder
    
    add_xhtml('toc', 'toc.xhtml')
    
    if @settings[:front_page]
      s = File.read(@settings[:front_page])
      s = s % { version: @settings[:version] }
      write_text_to_oebps_file(s, 'front.xhtml')
      add_xhtml('front', 'front.xhtml')
    end

    create_html_by_juan
    
    if @settings[:back_page]
      copy_oebps_file(@settings[:back_page], 'back.xhtml')
      add_xhtml('back', 'back.xhtml')
    end
    
    src = File.join(@settings[:template], 'epub.css')
    copy_oebps_file(src, 'cbeta.css')
    
    template = File.read(File.join(@settings[:template], 'content.opf.erb'))
    renderer = ERB.new(template)
    output = renderer.result(binding)
    fn = File.join(@temp_folder, 'OEBPS', 'content.opf')
    File.write(fn, output)
  end
  
  def prepare_todo_list(input_folder, output_folder)
    puts "prepare todo list: #{input_folder}"
    Dir.foreach(input_folder) do |f|
      next if f.start_with? '.'
      p1 = File.join(input_folder, f)
      if File.file?(p1)
        next unless f.end_with? '.xml'
        work = f.sub(/^([A-Z]{1,2})\d{2,3}n(.*)\.xml$/, '\1\2')
        work = 'T0220' if work.start_with? 'T0220'
        unless @todo.key? work
          @todo[work] = { xml_files: [] }
          folders = output_folder.split('/')
          folders.pop if folders[-1].match(/^[A-Z]{1,2}\d{2,3}$/)
          folder = folders.join('/')
          FileUtils::mkdir_p folder
          @todo[work][:epub] = File.join(folder, "#{work}.epub")
        end
        @todo[work][:xml_files] << p1
      else
        p2 = File.join(output_folder, f)
        prepare_todo_list(p1, p2)
      end
    end
  end
  
      
  def to_html(e)
    e.to_xml(encoding: 'UTF-8', pertty: true, :save_with => Nokogiri::XML::Node::SaveOptions::AS_XML)
  end

  def traverse(e, mode='html')
    r = ''
    e.children.each { |c| 
      s = handle_node(c, mode)
      if s.nil?
        puts "handle_node 回傳 nil"
        puts c.name
        abort "cbeta_epub2.rb 行號：#{__LINE__}"
      end
      r += s
    }
    r
  end

  def zip_epub(fn)
    path = File.expand_path(fn)
    File.delete fn if File.exist? path
    Dir.chdir(@temp_folder) do
      system "zip -0Xq #{path} mimetype"
      system "zip -Xr9Dq #{path} *"
    end
  end
  
end