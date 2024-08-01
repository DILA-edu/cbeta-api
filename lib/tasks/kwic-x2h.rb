require 'cgi'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'set'
require 'cbeta'

# Convert CBETA XML P5a to simple HTML
#
# * HTML 中除了純文字之外，只有行號標記
# * 每一卷 產生一個檔案
# 
# CBETA XML P5a 可由此取得: https://github.com/cbeta-git/xml-p5a
#
# @example for convert 大正藏第一冊:
#
#   c = CBETA::P5aToSimpleHTML.new('/PATH/TO/CBETA/XML/P5a', '/OUTPUT/FOLDER')
#   c.convert('T01')
#
class P5aToSimpleHTML
  # 內容不輸出的元素
  PASS=['back', 'teiHeader']

  private_constant :PASS

  # @param xml_root [String] 來源 CBETA XML P5a 路徑
  # @param output_root [String] 輸出 Text 路徑
  def initialize(xml_root, gaiji_base, output_root, opts={})
    @xml_root = xml_root
    @output_root = output_root
    @cbeta = CBETA.new
    @gaijis = CBETA::Gaiji.new
    @config = { multi_edition: false }
    @config.merge!(opts)
  end

  # 將 CBETA XML P5a 轉為 Simple HTML
  #
  # @example for convert 大正藏第一冊:
  #
  #   x2h = CBETA::P5aToText.new('/PATH/TO/CBETA/XML/P5a', '/OUTPUT/FOLDER')
  #   x2h.convert('T01')
  #
  # @example for convert 大正藏全部:
  #
  #   x2h = CBETA::P5aToText.new('/PATH/TO/CBETA/XML/P5a', '/OUTPUT/FOLDER')
  #   x2h.convert('T')
  #
  # @example for convert 大正藏第五冊至第七冊:
  #
  #   x2h = CBETA::P5aToText.new('/PATH/TO/CBETA/XML/P5a', '/OUTPUT/FOLDER')
  #   x2h.convert('T05..T07')
  #
  # T 是大正藏的 ID, CBETA 的藏經 ID 系統請參考: http://www.cbeta.org/format/id.php
  def convert(target=nil)
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
    Dir.entries(@xml_root).sort.each { |c|
      next if c.start_with? '.'
      next if c.size > 2
      handle_collection(c)
    }
  end

  def e_anchor(e)
    if e.has_attribute?('type')
      if e['type'] == 'circle'
        return '◎'
      end
    end

    ''
  end

  def e_corr(e)
    r = traverse(e)
    if @config[:multi_edition]
      r = "<r w='【CBETA】'>#{r}</r>"
    end
    r
  end
  
  def e_foreign(e)
    return '' if e.key?('place') and e['place'].include?('foot')
    traverse(e)
  end

  def e_g(e)
    # if 悉曇字、蘭札體
    #   使用 Unicode PUA
    # else if 有 <mapping type="unicode">
    #   直接採用
    # else if 有 <mapping type="normal_unicode">
    #   採用 normal_unicode
    # else if 有 normalized form
    #   採用 normalized form
    # else
    #   Unicode PUA
    gid = e['ref'][1..-1]
    g = @gaijis[gid]
    abort "Line:#{__LINE__} 無缺字資料:#{gid}" if g.nil?
    
    # 悉曇字 or 蘭札體
    if gid.start_with?('SD') or gid.start_with? 'RJ'
      return g['symbol'] if g.key?('symbol')
      return g['romanized'] if g.key?('romanized')
      return g['pua']
    end
    
    c = g['uni_char']
    return c unless c.nil? or c.empty?

    if @gaiji_norm.last
      c = g['norm_uni_char']
      return c unless c.nil? or c.empty?

      c = g['norm_big5_char']
      return c unless c.nil? or c.empty?
    end

    # Unicode PUA
    [0xf0000 + gid[2..-1].to_i].pack 'U'
  end

  def e_item(e)
    r = traverse(e)
    if e.key? 'n'
      r = e['n'] + r
    end
    r
  end
  
  def e_lb(e)
    return '' if e['type']=='old'
    return '' if e['ed'] != @series # 卍續藏裡有 新文豐 版行號

    @lb = e['n']
    r = %(<a \nid="lb#{@lb}"></a>)
    unless @next_line_buf.empty?
      r << @next_line_buf + "\n"
      @next_line_buf = ''
    end
    r
  end

  def e_lem(e)
    r = traverse(e)
    if @config[:multi_edition]
      w = e['wit'].scan(/【.*?】/)
      @editions.merge w
      w = w.join(' ')
      r = "<r w='#{w}'>#{r}</r>"
    end
    r
  end

  def e_milestone(e)
    r = ''
    if e['unit'] == 'juan'
      @juan = e['n'].to_i
      r << "<juan #{@juan}>"
      r << %(<a id="lb#{@lb}"></a>) unless @lb.nil?
    end
    r
  end

  def e_note(e)
    if e.has_attribute?('place')
      if "inline inline2 interlinear".include?(e['place'])
        r = traverse(e)
        return "<inline>(#{r})</inline>"
      end
    end
    ''
  end

  def e_rdg(e)
    return '' unless @config[:multi_edition]
    
    r = traverse(e)
    w = e['wit'].scan(/【.*?】/)
    @editions.merge w
    "<r w='#{e['wit']}'>#{r}</r>"
  end

  def e_reg(e)
    r = ''
    choice = e.at_xpath('ancestor::choice')
    r = traverse(e) if choice.nil?
    r
  end
  
  def e_sg(e)
    '(' + traverse(e) + ')'
  end

  def e_sic(e)
    return '' unless@config[:multi_edition]
    
    "<r w='#{@orig}'>" + traverse(e) + "</r>"
  end

  def handle_sutra(xml_fn)
    @sutra_no = File.basename(xml_fn, ".xml")
    print @sutra_no + ' '
    
    @dila_note = 0
    @div_count = 0
    @editions = Set.new ["【CBETA】"]
    @gaiji_norm = [true]
    @in_l = false
    @juan = 0
    @lg_row_open = false
    @mod_notes = Set.new
    @next_line_buf = ''
    @open_divs = []
    @lb = nil

    text = parse_xml(xml_fn)
   
    # 大正藏 No. 220 大般若經跨冊，CBETA 分成多檔並在檔尾加上 a, b, c....
    # 輸出時去掉這些檔尾的 a, b, b....
    if @sutra_no.match(/^(T05|T06|T07)n0220/)
      @sutra_no = "#{$1}n0220"
    end

    @out_sutra = File.join(@out_vol, @sutra_no)
    FileUtils.makedirs @out_sutra

    juans = text.split(/(<juan \d+>)/)
    juan_no = nil
    buf = ''
    # 一卷一檔
    juans.each { |j|
      if j =~ /<juan (\d+)>$/
        juan_no = $1.to_i
      else
        if juan_no.nil?
          buf = j
        else
          write_juan(juan_no, buf+j)
          buf = ''
        end
      end
    }
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
      return r if tt['rend'] == 'inline'
      return r if tt['rend'] == 'normal'
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

  def e_unclear(e)
    r = traverse(e)
    r = '▆' if r.empty?
    r
  end

  def handle_text(e)
    s = e.content().chomp
    return '' if s.empty?
    return '' if e.parent.name == 'app'

    # cbeta xml 文字之間會有多餘的換行
    r = s.gsub(/[\n\r]/, '')

    # 把 & 轉為 &amp;
    CGI.escapeHTML(r)
  end

  def e_tt(e)
    @tt_type = e['type']
    traverse(e)
  end
  
  def handle_collection(c)
    @series = c
    puts 'handle_collection ' + c

    dest = File.join(@output_root, @series)
    puts "清除舊資料: #{dest}"
    FileUtils.remove_dir(dest, true)

    folder = File.join(@xml_root, @series)
    Dir.entries(folder).sort.each { |vol|
      next if vol.start_with? '.'
      handle_vol(vol)
    }
  end

  def handle_node(e)
    return '' if e.comment?
    return handle_text(e) if e.text?
    return '' if PASS.include?(e.name)
    r = case e.name
    when 'anchor'    then e_anchor(e)
    when 'back'      then ''
    when 'corr'      then e_corr(e)
    when 'foreign'   then e_foreign(e)
    when 'g'         then e_g(e)
    when 'graphic'   then ''
    when 'item'      then e_item(e)
    when 'lb'        then e_lb(e)
    when 'lem'       then e_lem(e)
    when 'mulu'      then ''
    when 'note'      then e_note(e)
    when 'milestone' then e_milestone(e)
    when 'rdg'       then e_rdg(e)
    when 'reg'       then e_reg(e)
    when 'sic'       then e_sic(e)
    when 'sg'        then e_sg(e)
    when 'tt'        then e_tt(e)
    when 't'         then e_t(e)
    when 'term'      then e_term(e)
    when 'text'      then e_text(e)
    when 'teiHeader' then ''
    when 'unclear'   then e_unclear(e)
    else traverse(e)
    end
    r
  end  

  def handle_vol(vol)
    puts "\nconvert volumn: #{vol}"


    @vol = vol
    @series = CBETA.get_canon_from_vol(vol)
    
    @orig = @cbeta.get_canon_symbol(@series)
    abort "未處理底本" if @orig.nil?
    @orig_short = @orig.sub(/^【(.*)】$/, '\1')
    
    @out_vol = File.join(@output_root, @series, vol)
    FileUtils.remove_dir(@out_vol, true)
    FileUtils.makedirs @out_vol
    
    source = File.join(@xml_root, @series, vol)
    Dir[source+"/*"].each { |f|
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

  def open_xml(fn)
    s = File.read(fn)
    doc = Nokogiri::XML(s)
    doc.remove_namespaces!()
    doc
  end

  def parse_xml(xml_fn)
    doc = open_xml(xml_fn)        
    root = doc.root()

    text_node = root.at_xpath("text")
    handle_node(text_node)
  end

  def traverse(e)
    r = ''
    e.children.each { |c| r << handle_node(c) }
    r
  end

  def write_juan(juan_no, txt)
    if @config[:multi_edition]
      write_juan_for_editions(juan_no, txt)
    else
      fn = File.join(@out_sutra, "%03d.html" % juan_no)
      write_juan_to_file(fn, txt)
    end
  end
  
  def write_juan_for_editions(juan_no, txt)
    folder = File.join(@out_sutra, "%03d" % juan_no)
    FileUtils.makedirs(folder)
    @editions.each do |ed|
      frag = Nokogiri::XML.fragment(txt)
      frag.search("r").each do |node|
        if node['w'] == ed
          node.add_previous_sibling(node.text)
        end
        node.remove
      end
      html = to_html(frag)

      fn = ed.sub(/^【(.*?)】$/, '\1')
      if fn != 'CBETA' and fn != @orig_short
        fn = @orig_short + '→' + fn
      end
      fn = "#{fn}.html"
      output_path = File.join(folder, fn)
      write_juan_to_file(output_path, html)
    end
  end
  
  def write_juan_to_file(fn, html)
    text = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
      </head>
      <body>#{html}</body>
      </html>
    HTML
    File.write(fn, text)
  end

end
