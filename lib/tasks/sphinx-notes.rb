require 'cgi'
require 'chronic_duration'
require 'date'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'set'
require 'cbeta'
require_relative 'cbeta_p5a_share'
require_relative 'html-node'
require_relative 'share'
require_relative 'sphinx-share'

# 產生 sphinx 所需的 xml 檔案
class SphinxNotes
  # 內容不輸出的元素
  PASS = %w[anchor back figDesc mulu pb rdg sic teiHeader]
  
  MISSING = '－'  # 某版用字缺的符號
  AROUND = 100 # 夾注前後文字數
  
  private_constant :PASS, :MISSING

  def initialize
    @xml_root = Rails.application.config.cbeta_xml
    @cbeta = CBETA.new
    @gaijis = MyCbetaShare.get_cbeta_gaiji
    @gaijis_skt = MyCbetaShare.get_cbeta_gaiji_skt
    @dynasty_labels = read_dynasty_labels
  end

  def convert(target=nil)
    t1 = Time.now
    @stat = Hash.new(0)
    @sphinx_doc_id = 0
    fn = Rails.root.join('data', 'sphinx-xml', 'notes.xml')
    @fo = File.open(fn, 'w')
    @fo.puts %(<?xml version="1.0" encoding="utf-8"?>)
    @fo.puts "<sphinx:docset>"
    
    if target.nil?
      convert_all
    else
      arg = target.upcase
      if arg.size.between?(1,2)
        convert_canon(arg)
      else
        puts "因為某些佛典單卷跨冊，轉檔必須以某部藏經為單位，例如參數 T 表示轉換整個大正藏。"
      end
    end

    @fo.write '</sphinx:docset>'
    @fo.close
    puts <<~MSG
      \n--------------------
      原書校注數量：#{@stat[:foot]}
      CBETA校注數量：#{@stat[:add]}
      註解總數：#{@stat.values.sum}
    MSG
    puts "花費時間：" + ChronicDuration.output(Time.now - t1)
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
  
  def before_parse_xml(xml_fn)
    @back = { 0 => '' }
    @back_orig = { 0 => '' }
    @dila_note = 0
    @gaiji_norm = [true]
    @in_l = false
    @juan = 0
    @lg_row_open = false
    @mod_notes = Set.new
    @next_line_buf = ''
    @notes_mod = {}
    @notes_orig = {}
    @notes_add = {}
    @offset = 0
    @sutra_no = File.basename(xml_fn, ".xml")
    @work_id = CBETA.get_work_id_from_file_basename(@sutra_no)
    @work_info = get_info_from_work(@work_id)
  end

  def convert_all
    each_canon(@xml_root) do |c|
      convert_canon(c)
    end
  end
  
  def convert_canon(c)
    @canon = c
    print "\nconvert canon: #{c}"
    @canon_order = CBETA.get_sort_order_from_canon_id(c)

    folder = File.join(@xml_root, @canon)
    Dir.entries(folder).sort.each do |vol|
      next if vol.start_with? '.'
      convert_vol(vol)
    end
  end
  
  def convert_sutra(xml_fn)
    print "\nsphinx-notes.rb #{File.basename(xml_fn, '.*')}"
    t1 = Time.now
    before_parse_xml(xml_fn)
    @text = parse_xml(xml_fn)
    write_notes_for_sphinx
  end
  
  def convert_vol(vol)
    canon = CBETA.get_canon_from_vol(vol)
    @orig = @cbeta.get_canon_symbol(canon)
    abort "未處理底本" if @orig.nil?
    @orig_short = @orig.sub(/^【(.*)】$/, '\1')

    @vol = vol
    
    source = File.join(@xml_root, @canon, vol)
    Dir.entries(source).sort.each do |f|
      next if f.start_with? '.'
      fn = File.join(source, f)
      convert_sutra(fn)
    end
  end
  
  def e_app(e, mode)
    if mode=='note'
      lem = e.at('lem')
      return traverse(lem, mode)
    end
    traverse(e, mode)
  end

  def e_g(e, mode)
    @offset += 1 unless mode == 'note'

    gid = e['ref'][1..-1]
    
    if gid.start_with? 'CB'
      g = @gaijis[gid]
    else
      g = @gaijis_skt[gid]
    end
    
    abort "Line:#{__LINE__} 無缺字資料:#{gid}" if g.nil?
    zzs = g['composition']
    
    if gid.start_with?('SD')
      return g['symbol'] if g.key?('symbol')
      return g['romanized'] if g.key?('romanized')
      return CBETA.pua(gid)
    end
   
    if g.key?('unicode') and (not g['unicode'].empty?)
      return g['uni_char'] # 直接採用 unicode
    end

    # 註解常有用字差異，不用通用字，否則會變成兩個版本的用字一樣
    # 例：T02n0099, 181b08, 註：㝹【CB】，[少/免]【大】
    if @gaiji_norm.last # 如果 沒有特別說 不能用 通用字
      if g.key?('norm_uni_char') and (not g['norm_uni_char'].empty?)
        return g['norm_uni_char']
      end

      c = g['norm_big5_char']
      unless c.nil? or c.empty?
        return c
      end
    end

    CBETA.pua(gid)
  end

  def e_lb(e, mode)
    return '' if e['type']=='old'
    return '' if e['ed'] != @canon
    
    @lb = e['n']
    @linehead = CBETA.get_linehead(@sutra_no, e['n'])

    ''
  end

  def e_lem(e, mode)
    app = e.parent
    if app.key?('n')
      n = app['n']
      if @notes_mod[@juan].key?(n)
        @notes_mod[@juan][n][:text] << e_lem_cf(e)
      end
    end

    traverse(e, mode)
  end

  def e_lem_cf(e)
    cfs = []
    e.xpath('note').each do |c|
      next unless c.key?('type')
      next unless c['type'].match(/^cf\d+$/)
      cfs << traverse(c, 'note')
    end

    return '' if cfs.empty?

    s = cfs.join('; ')
    "(cf. #{s})"
  end

  def e_milestone(e)
    if e['unit'] == 'juan'
      @juan = e['n'].to_i
      @back[@juan] = @back[0]
      @back_orig[@juan] = @back_orig[0]
      @first_lb_in_juan = true
      @notes_mod[@juan] = {}
      @notes_orig[@juan] = {}
      @notes_add[@juan] = []
      print " #{@juan}"
    end
    ''
  end

  def e_note(e, mode)
    return '' if mode == 'note'
    return '' if e['rend'] == 'hide'
      
    n = e['n']
    if e.has_attribute?('type')
      t = e['type']
      case t
      when 'add'
        n = @notes_add[@juan].size + 1
        n = "cb_note_#{n}"
        s = traverse(e, 'note')
        s << e_note_add_cf(e)
        @notes_add[@juan] << { lb: @lb, text: s }
      when 'equivalent', 'rest' then return ''
      when 'orig'       then return e_note_orig(e)
      when 'mod'
        @notes_mod[@juan][n] = { 
          lb: @lb, 
          text: traverse(e, 'note')
        }
        return ""
      when 'star'
        return ''
      else
        return '' if t.start_with?('cf')
      end
    end

    if e.has_attribute?('resp')
      return '' if e['resp'].start_with? 'CBETA'
    end

    return traverse(e)
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
  
  def e_note_orig(e)
    n = e['n']
    subtype = e['subtype']
    s = traverse(e, 'note')
    @notes_orig[@juan][n] = s
    @notes_mod[@juan][n] = { lb: @lb, text: s }
    
    return ''
  end
  
  def e_reg(e)
    r = ''
    choice = e.at_xpath('ancestor::choice')
    r = traverse(e) if choice.nil?
    r
  end

  def e_unclear(e, mode)
    r = traverse(e, mode)
    if r.empty?
      r = '▆'
      @offset += 1 unless mode == 'note'
    end
    r
  end  

  def handle_node(e, mode='text')
    return '' if e.comment?
    
    if e.text?
      return e.text if mode =='note'
      return handle_text(e, mode)
    end

    return '' if PASS.include?(e.name)

    norm = true
    if e['behaviour'] == "no-norm"
      norm = false
    end
    @gaiji_norm.push norm

    puts e.name if e.name.include?('mulu')
    r = case e.name
    when 'app'       then e_app(e, mode)
    when 'g'         then e_g(e, mode)
    when 'lb'        then e_lb(e, mode)
    when 'lem'       then e_lem(e, mode)
    when 'note'      then e_note(e, mode)
    when 'milestone' then e_milestone(e)
    when 'reg'       then e_reg(e)
    when 'unclear'   then e_unclear(e, mode)
    else traverse(e, mode)
    end

    @gaiji_norm.pop
    r
  end
  
  def handle_text(e, mode)
    s = e.content().chomp
    return '' if s.empty?
    return '' if e.parent.name == 'app'

    # cbeta xml 文字之間會有多餘的換行
    s.gsub(/[\n\r]/, '')

    @offset += s.size unless mode == 'note'
    s
  end

  def open_xml(fn)
    s = File.read(fn)
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
    #@pass = [false]

    doc = open_xml(xml_fn)
    
    e = doc.xpath("//titleStmt/title")[0]
    @title = traverse(e, 'txt')
    @title = @title.split()[-1]
    
    read_mod_notes(doc)

    root = doc.root()
    text_node = root.at_xpath("text")
    #@pass = [true]
    
    @offset = 0
    handle_node(text_node)
  end
  
  def traverse(e, mode='text')
    r = ''
    e.children.each { |c| 
      s = handle_node(c, mode)
      abort "handle_node return nil, element: #{c.name}" if s.nil?
      r << s
    }
    r
  end

  def write_notes_for_sphinx
    all_notes = {}
    @notes_mod.each_pair do |juan, notes|
      @stat[:foot] += notes.size
      all_notes[juan] = []
      notes.each_pair do |n, note|
        write_sphinx_doc(juan, note, n: "n#{n}")
        note[:n] = n
        all_notes[juan] << note
      end
    end

    @notes_add.each_pair do |juan, notes|
      @stat[:add] += notes.size
      all_notes[juan] = [] unless all_notes.key?(juan)
      notes.each_with_index do |note, i|
        write_sphinx_doc(juan, note, n: "cb_note_#{i+1}")
        note[:n] = "A#{i+1}"
        all_notes[juan] << note
      end
    end

    write_footnotes_for_download(all_notes)
  end

  def write_footnotes_for_download(all_notes)
    folder = Rails.root.join('data', 'download', 'footnotes', @canon, @work_id)
    FileUtils.makedirs(folder)
    all_notes.each_pair do |juan, notes|
      fn = File.join(folder, "%03d.csv" % juan)
      notes.sort_by! { |x| x[:lb] + x[:n] }
      CSV.open(fn, "wb") do |csv|
        csv << %w[頁碼行號 校注編號 校注內容]
        notes.each do |note|
          csv << [note[:lb], note[:n], note[:text]]
        end
      end
    end
  end

  def write_sphinx_doc(juan, note, n: nil)
    @sphinx_doc_id += 1
    xml = <<~XML
      <sphinx:document id="#{@sphinx_doc_id}">
        <canon>#{@canon}</canon>
        <canon_order>#{@canon_order}</canon_order>
        <vol>#{@vol}</vol>
        <file>#{@sutra_no}</file>
        <work>#{@work_id}</work>
        <juan>#{juan}</juan>
        <lb>#{note[:lb]}</lb>
    XML

    xml << "  <n>#{n}</n>\n" unless n.nil?

    s1 = note[:text].encode(xml: :text)
    xml << "  <content>#{s1}</content>\n"

    @work_info.each_pair do |k,v|
      xml << "  <#{k}>#{v}</#{k}>\n"
    end

    xml << "</sphinx:document>\n"
    @fo.puts xml
  end

  def text_around_note(note)
    i = note[:offset] - AROUND

    if i < 0
      i = 0
      length = note[:offset]
    else
      length = AROUND
    end

    s = @text[i, length]
    s = s.encode(xml: :text)
    r = "  <prefix>#{s}</prefix>\n"

    i = note[:offset] + note[:text].size + 2
    s = @text[i, AROUND]
    if s.nil?
      puts "text size: #{@text.size}"
      puts "offset: #{i}"
      puts note.inspect
      abort "#{__LINE__}"
    end
    s = s.encode(xml: :text)
    r + "  <suffix>#{s}</suffix>\n"
  end

  include CbetaP5aShare
  include SphinxShare
end
