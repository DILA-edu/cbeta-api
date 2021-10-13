require 'cgi'
require 'date'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'set'
require_relative 'share'
require_relative 'cbeta_p5a_share'

# Convert CBETA XML P5a to Text
#
# CBETA XML P5a 可由此取得: https://github.com/cbeta-git/xml-p5a
class P5aToText
  # 內容不輸出的元素
  PASS = %w(back graphic mulu rdg sic teiHeader)
  BLOCK_NODES = %w(byline cell docNumber figure head juan list p)
  
  private_constant :PASS

  # @param xml_root [String] 來源 CBETA XML P5a 路徑
  # @param output_root [String] 輸出 Text 路徑
  # @option opts [String] :encoding 輸出編碼，預設 'UTF-8'
  # @option opts [String] :gaiji 缺字處理方式，預設 'default'
  #   * 'PUA': 缺字一律使用 Unicode PUA
  #   * 'default': 優先使用通用字
  def initialize(xml_root, output_root, opts={})
    @xml_root = xml_root
    @output_root = output_root
    
    @settings = {
      encoding: 'UTF-8',
      gaiji: 'default'
    }
    @settings.merge!(opts)
    
    @cbeta = CBETA.new
    @gaijis = MyCbetaShare.get_cbeta_gaiji
    @gaijis_skt = MyCbetaShare.get_cbeta_gaiji_skt
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

  # 跨行字詞移到下一行
  def appify(text)
    r = ''
    i = 0
    app = ''
    text.each_line do |line|
      line.chomp!
      if line.match(/^(.*)║(.*)$/)
        r += $1
        t = $2
        r += "(%02d)" % i
        r += "║#{app}"
        app = ''
        i = 0
        chars = t.chars
        until chars.empty?
          c = chars.pop
          if c == "\t"
            break
          elsif ' 　：》」』、；，！？。'.include? c
            chars << c
            break
          elsif '《「『'.include? c  # 這些標點移到下一行
            app = c + app
            break
          else
            app = c + app
          end
        end
        r += chars.join.gsub(/\t/, '') + "\n"
        i = app.size
      end
    end
    r
  end

  def convert_all
    each_canon(@xml_root) do |c|
      handle_canon(c)
    end
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

    if gid.start_with? 'CB'
      g = @gaijis[gid]
    else
      g = @gaijis_skt[gid]
    end

    abort "Line:#{__LINE__} 無缺字資料:#{gid}" if g.nil?
    
    if @settings[:gaiji] == 'PUA'
      return g['pua'] if gid.start_with?('SD') # 悉曇字
      return g['pua'] if gid.start_with?('RJ') # 蘭札體
      return CBETA.pua(gid)
    end
    
    # 悉曇字 或 蘭札體
    if gid.start_with?('SD') or gid.start_with?('RJ')
      return g['symbol'] unless g['symbol'].blank?
      return (g['romanized']+' ') unless g['romanized'].blank?
      return g['pua']
    end
    
    return g['uni_char'] unless g['uni_char'].blank?

    if @gaiji_norm.last
      return g['norm_uni_char'] unless g['norm_uni_char'].blank?
      return g['norm_big5_char'] unless g['norm_big5_char'].blank?
    end
    
    # Unicode PUA
    [0xf0000 + gid[2..-1].to_i].pack 'U'
  end

  def e_item(e)
    r = traverse(e)
    if e.key? 'n'
      r = e['n'] + r
    end
    r + "\n"
  end
  
  def e_l(e)
    r = traverse(e)
    r += "\n" unless @lg_type == 'abnormal'
    r
  end

  def e_lb(e)
    return '' if e['type']=='old'
    r = ''
    unless @next_line_buf.empty?
      r += @next_line_buf + "\n"
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
    if e.has_attribute?('place')
      if "inline inline2 interlinear".include?(e['place'])
        r = traverse(e)
        return "（#{r}）"
      end
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

    # 不是雙行對照
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

  def handle_canon(c)
    @canon = c
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
    return traverse(e)+"\n" if BLOCK_NODES.include?(e.name)
    
    r = case e.name
    when 'anchor'    then e_anchor(e)
    when 'foreign'   then e_foreign(e)
    when 'g'         then e_g(e)
    when 'item'      then e_item(e)
    when 'l'         then e_l(e)
    when 'lb'        then e_lb(e)
    when 'note'      then e_note(e)
    when 'milestone' then e_milestone(e)
    when 'reg'       then e_reg(e)
    when 'sg'        then e_sg(e)
    when 'tt'        then e_tt(e)
    when 't'         then e_t(e)
    when 'term'      then e_term(e)
    when 'text'      then e_text(e)
    when 'unclear'   then ele_unclear(e)
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
    s = e.content().chomp
    return '' if s.empty?
    return '' if e.parent.name == 'app'

    # cbeta xml 文字之間會有多餘的換行
    s.gsub(/[\n\r]/, '')
  end

  def handle_vol(vol)
    $stderr.puts "sphinx x2t #{vol}"

    @canon = CBETA.get_canon_from_vol(vol)
    @orig = @cbeta.get_canon_symbol(@canon)
    abort "未處理底本" if @orig.nil?

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
    e.children.each { |c| 
      s = handle_node(c)
      puts "handle_node return nil, node: " + c.to_s if s.nil?
      r += s
    }
    r
  end

  def write_juan(juan_no, txt)
    fn = File.join(@out_sutra, "%03d.txt" % juan_no)
    fo = File.open(fn, 'w', encoding: @settings[:encoding])
    fo.write(txt)
    fo.close
  end
  
  include CbetaP5aShare
end