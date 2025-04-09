require 'cgi'
require 'colorize'
require 'date'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'set'
require_relative '../cbeta_p5a_share'

# Convert CBETA XML P5a to Text
#
# CBETA XML P5a 可由此取得: https://github.com/cbeta-git/xml-p5a
#
# @example for convert 大正藏第一冊 in app format:
#
#   c = CBETA::P5aToText.new('/PATH/TO/CBETA/XML/P5a', '/OUTPUT/FOLDER', 'app')
#   c.convert('T01')
#
class P5aToText
  # 內容不輸出的元素
  PASS=['back', 'mulu', 'rdg', 'sic', 'teiHeader']
  
  private_constant :PASS

  # @param xml_root [String] 來源 CBETA XML P5a 路徑
  # @param output_root [String] 輸出 Text 路徑
  # @option opts [String] :encoding 輸出編碼，預設 'UTF-8'
  # @option opts [String] :gaiji 缺字處理方式，預設 'default'
  # @option opts [String] :inline_note 是否呈現夾注，預設為 true
  #   * 'PUA': 缺字一律使用 Unicode PUA
  #   * 'default': 優先使用通用字
  def initialize(xml_root, output_root, opts={})
    @xml_root = xml_root
    @output_root = output_root
    
    @settings = {
      encoding: 'UTF-8',
      gaiji: 'default',
      inline_note: true
    }
    @settings.merge!(opts)
    
    @cbeta = CBETA.new
    @gaijis = CBETA::Gaiji.new
    @us = UnicodeService.new
  end

  # 將 CBETA XML P5a 轉為 Text
  #
  # @example for convert all:
  #
  #   x2h = CBETA::P5aToText.new('/PATH/TO/CBETA/XML/P5a', '/OUTPUT/FOLDER')
  #   x2h.convert
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
      handle_canon(arg)
    else
      if arg.include? '..'
        arg.match(/^([^\.]+?)\.\.([^\.]+)$/) {
          handle_vols($1, $2)
        }
      else
        handle_vol(arg)
      end
    end
    puts "完成"
  end

  private

  def convert_all
    each_canon(@xml_root) do |c|
      handle_canon(c)
    end
    puts "完成".green
  end

  def e_anchor(e)
    if e.has_attribute?('type')
      if e['type'] == 'circle'
        return '◎'
      end
    end

    ''
  end

  def e_foreign(e)
    return '' if e.key?('place') and e['place'].include?('foot')
    traverse(e)
  end
  
  def e_g(e)
    gid = e['ref'][1..-1]    
    g = @gaijis[gid]
    abort "Line:#{__LINE__} 無缺字資料:#{gid}" if g.nil?
    
    if gid.start_with?('SD') # 悉曇字
      case gid
      when 'SD-E35A'
        return '（'
      when 'SD-E35B'
        return '）'
      else
        s = g['romanized']
        if s.nil? or s.empty?
          return '◇'
        else
          return s
        end
      end
    end
    
    if gid.start_with?('RJ') # 蘭札體
      s = g['romanized']
      if s.nil? or s.empty?
        return '◇'
      else
        return s
      end
    end
    
    return g['uni_char'] if g.key?('unicode')

    if @gaiji_norm.last # 如果 沒有特別說 不能用 通用字
      return g['norm_uni_char'] if g.key?('norm_uni_char')

      s = g['norm_big5_char']
      return s unless s.blank?
    end

    g['composition']
  end

  def e_lb(e)
    return '' if e['type']=='old'
    r = ''
    if e['ed'] == @canon
      r += "\n" + CBETA.get_linehead(@sutra_no, e['n']) + '║'
    end
    unless @next_line_buf.empty?
      r += @next_line_buf
      @next_line_buf = ''
    end
    r
  end

  def e_milestone(e)
    r = ''
    if e['unit'] == 'juan'
      @juan = e['n'].to_i
      r += "<juan #{@juan}>"
    end
    r
  end

  def e_note(e)
    return '' unless @settings[:inline_note]
    return '' if e['type']=='add'
    
    if e.has_attribute?('place') 
      if %w(inline inline2 interlinear).include? e['place']
        r = traverse(e)
        return "（#{r}）"
      end
    end
    
    if e['type'] == 'authorial'
      return traverse(e)
    end
    
    ''
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

  def handle_canon(c)
    @canon = c
    puts "\nhandle_canon " + c
    folder = File.join(@xml_root, @canon)
    Dir.entries(folder).sort.each do |vol|
      next if vol.start_with? '.'
      handle_vol(vol)
    end
  end

  def handle_node(e)
    return '' if e.comment?
    return handle_text(e) if e.text?
    return '' if PASS.include?(e.name)
    r = case e.name
    when 'anchor'    then e_anchor(e)
    when 'foreign'   then e_foreign(e)
    when 'g'         then e_g(e)
    when 'graphic'   then '【圖】'
    when 'lb'        then e_lb(e)
    when 'note'      then e_note(e)
    when 'milestone' then e_milestone(e)
    when 'reg'       then e_reg(e)
    when 'sg'        then e_sg(e)
    when 't'         then e_t(e)
    when 'term'      then e_term(e)
    when 'text'      then e_text(e)
    when 'tt'        then e_tt(e)
    when 'unclear'   then '▆'
    else traverse(e)
    end
    r
  end

  def handle_sutra(xml_fn)
    @dila_note = 0
    @div_count = 0
    @gaiji_norm = [true]
    @in_l = false
    @juan = 0
    @lg_row_open = false
    @mod_notes = Set.new
    @next_line_buf = ''
    @open_divs = []
    @sutra_no = File.basename(xml_fn, ".xml")

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

  def handle_text(e)
    s = e.content()
    return '' if s.empty?
    return '' if e.parent.name == 'app'
    s.gsub(/[\r\n\t]/, '')
  end

  def handle_vol(vol)
    print vol + ' '

    @canon = CBETA.get_canon_from_vol(vol)
    @vol = vol
    @out_vol = File.join(@output_root, @canon, vol)
    FileUtils.remove_dir(@out_vol, true)
    FileUtils.makedirs @out_vol
    
    source = File.join(@xml_root, @canon, vol)
    Dir.entries(source).sort.each { |f|
      next if f.start_with? '.'
      fn = File.join(source, f)
      handle_sutra(fn)
    }
  end

  def handle_vols(v1, v2)
    puts "convert volumns: #{v1}..#{v2}"
    @canon = get_canon_from_vol(v1)
    folder = File.join(@xml_root, @canon)
    Dir.entries(folder).sort.each do |vol|
      next if vol < v1
      next if vol > v2
      handle_vol(vol)
    end
  end

  def open_xml(fn)
    s = File.read(fn)
    s.gsub!(/(<lb[^>]+\/>)\n(<milestone)/, '\1\2')
    s.gsub!(/(<pb[^>]+>)\n(<lb)/, '\1\2')
    
    doc = Nokogiri::XML(s)
    doc.remove_namespaces!()
    doc
  end

  def parse_xml(xml_fn)
    doc = open_xml(xml_fn)    
    root = doc.root()    

    text = root.xpath("text")[0]
    handle_node(text)
  end

  def traverse(e)
    r = ''
    e.children.each { |c| 
      s = handle_node(c)
      puts "handle_node return nil, node: " + c.to_s if s.nil?
      r += s
    }
    r
  end

  def write_juan(juan_no, txt)
    fn = "%03d.txt" % juan_no
    fn = File.join(@out_sutra, fn)

    fo = File.open(fn, 'w', encoding: @settings[:encoding])
    fo.write(txt.lstrip)
    fo.close
  end

  include CbetaP5aShare
end
