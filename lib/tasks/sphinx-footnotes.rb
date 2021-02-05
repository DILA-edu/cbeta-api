require 'cgi'
require 'chronic_duration'
require 'date'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'set'
require 'cbeta'
require_relative 'html-node'
require_relative 'share'

class SphinxFootnotes
  # 內容不輸出的元素
  PASS=['anchor', 'back', 'figDesc', 'pb', 'rdg', 'sic', 'teiHeader']
  
  # 某版用字缺的符號
  MISSING = '－'
  
  private_constant :PASS, :MISSING

  def initialize
    @xml_root = Rails.application.config.cbeta_xml
    @cbeta = CBETA.new
    @gaijis = MyCbetaShare.get_cbeta_gaiji
    @gaijis_skt = MyCbetaShare.get_cbeta_gaiji_skt
  end

  def convert(target=nil)
    t1 = Time.now
    @sphinx_doc_id = 0
    fn = Rails.root.join('data', 'cbeta-xml-for-sphinx', 'footnotes.xml')
    @footnotes = File.open(fn, 'w')
    @footnotes.puts %(<?xml version="1.0" encoding="utf-8"?>)
    @footnotes.puts "<sphinx:docset>"
    
    if target.nil?
      convert_all
    else
      arg = target.upcase
      if arg.size.between?(1,2)
        convert_canon(arg)
      else
        puts "因為某些典籍單卷跨冊，轉檔必須以某部藏經為單位，例如參數 T 表示轉換整個大正藏。"
      end
    end

    @footnotes.write '</sphinx:docset>'
    @footnotes.close
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
    @div_count = 0
    @gaiji_norm = [true]
    @in_l = false
    @juan = 0
    @lg_row_open = false
    @mod_notes = Set.new
    @next_line_buf = ''
    @notes_mod = {}
    @notes_orig = {}
    @notes_add = {}
    @sutra_no = File.basename(xml_fn, ".xml")
    $stderr.print "\nsphinx-footnotes #{@sutra_no}"
    @work_id = CBETA.get_work_id_from_file_basename(@sutra_no)
    @work_info = get_info_from_work(@work_id)
  end

  def convert_all
    Dir.entries(@xml_root).sort.each do |c|
      next unless c.match(/^#{CBETA::CANON}$/)
      convert_canon(c)
    end
  end
  
  def convert_canon(c)
    @canon = c
    $stderr.puts 'convert canon: ' + c
    folder = File.join(@xml_root, @canon)
    
    Dir.entries(folder).sort.each do |vol|
      next if vol.start_with? '.'
      convert_vol(vol)
    end
  end
  
  def convert_sutra(xml_fn)
    before_parse_xml(xml_fn)

    text = parse_xml(xml_fn)
    write_footnotes_for_sphinx
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
    if mode=='footnote'
      lem = e.at('lem')
      return traverse(lem, mode)
    end
    traverse(e, mode)
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

    if gid.start_with?('SD')
      return g['symbol'] if g.key? 'symbol'
      return "<span class='siddam' roman='#{g['romanized']}' code='#{gid}' char='#{g['char']}'/>"
    end
    
    if gid.start_with?('RJ')
      return "<span class='ranja' roman='#{g['romanized']}' code='#{gid}' char='#{g['char']}'/>"
    end
   
    if g.key?('unicode') and (not g['unicode'].empty?)
      return g['uni_char'] # 直接採用 unicode
    end

    nor = ''
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

    abort "缺組字式：#{gid}" if zzs.blank?
    return zzs
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
        @notes_mod[@juan][n][:text] += e_lem_cf(e)
      end
    end

    traverse(e, mode)
  end

  def e_lem_cf(e)
    cfs = []
    e.xpath('note').each do |c|
      next unless c.key?('type')
      next unless c['type'].match(/^cf\d+$/)
      cfs << traverse(c, 'footnote')
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
    return '' if mode == 'footnote'
      
    n = e['n']
    if e.has_attribute?('type')
      t = e['type']
      case t
      when 'add'
        n = @notes_add[@juan].size + 1
        n = "cb_note_#{n}"
        s = traverse(e, 'footnote')
        s += e_note_add_cf(e)
        @notes_add[@juan] << { lb: @lb, text: s }
      when 'equivalent', 'rest' then return ''
      when 'orig'       then return e_note_orig(e)
      when 'mod'
        @notes_mod[@juan][n] = { 
          lb: @lb, 
          text: traverse(e, 'footnote') 
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
    s = traverse(e, 'footnote')
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
    r = '▆' if r.empty?
    r
  end
  
  def get_info_from_work(work)
    w = Work.find_by n: work
    abort "在 works table 裡找不到 #{work}" if w.nil?
    
    data = { 
      title: w.title,
      category: w.category,
      category_ids: w.category_ids
    }
    data[:dynasty]          = w.time_dynasty unless w.time_dynasty.nil?
    data[:time_from]        = w.time_from    unless w.time_from.nil?
    data[:time_to]          = w.time_to      unless w.time_to.nil?
    data[:creators]         = w.creators         unless w.creators_with_id.nil?
    data[:creators_with_id] = w.creators_with_id unless w.creators_with_id.nil?

    return data if w.creators_with_id.nil?
    
    a = []
    w.creators_with_id.split(';').each do |creator|
      creator.match(/A(\d{6})/) do
        a << $1.to_i.to_s
      end
    end
    data[:creator_id] = a.join(',')
    data
  end

  def handle_node(e, mode='html')
    return '' if e.comment?
    
    if e.text?
      if mode == 'footnote'
        return handle_text(e, mode)
      else
        return ''
      end
    end

    return '' if PASS.include?(e.name)

    norm = true
    if e['behaviour'] == "no-norm"
      norm = false
    end
    @gaiji_norm.push norm

    r = case e.name
    when 'app'       then e_app(e, mode)
    when 'div', 'p'
      traverse(e, mode)
      ''
    when 'g'         then e_g(e, mode)
    when 'graphic'   then '【圖】'
    when 'lb'        then e_lb(e, mode)
    when 'lem'       then e_lem(e, mode)
    when 'note'      then e_note(e, mode)
    when 'milestone' then e_milestone(e)
    when 'reg'       then e_reg(e)
    when 'sic'       then e_sic(e, mode)
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
    @pass = [false]

    doc = open_xml(xml_fn)
    
    e = doc.xpath("//titleStmt/title")[0]
    @title = traverse(e, 'txt')
    @title = @title.split()[-1]
    
    read_mod_notes(doc)

    root = doc.root()
    text_node = root.at_xpath("text")
    @pass = [true]
    
    text = handle_node(text_node)
    text
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

  def write_footnotes_for_sphinx
    all_notes = {}
    @notes_mod.each_pair do |juan, notes|
      all_notes[juan] = []
      notes.each_pair do |n, note|
        write_sphinx_doc(juan, "n#{n}", note)
        note[:n] = n
        all_notes[juan] << note
      end
    end

    @notes_add.each_pair do |juan, notes|
      all_notes[juan] = [] unless all_notes.key?(juan)
      notes.each_with_index do |note, i|
        write_sphinx_doc(juan, "cb_note_#{i+1}", note)
        note[:n] = "A#{i+1}"
        all_notes[juan] << note
      end
    end
    write_footes_for_download(all_notes)
  end

  def write_footes_for_download(all_notes)
    folder = Rails.root.join('public', 'download', 'footnotes', @canon, @work_id)
    FileUtils.makedirs(folder)
    all_notes.each_pair do |juan, notes|
      fn = File.join(folder, "%03d.csv" % juan)
      notes.sort_by! { |x| x[:lb] + x[:n] }
      CSV.open(fn, "wb") do |csv|
        csv << %w[頁碼行號 校註編號 校註內容]
        notes.each do |note|
          csv << [note[:lb], note[:n], note[:text]]
        end
      end
    end
  end

  def write_sphinx_doc(juan, n, note)
    @sphinx_doc_id += 1
    s1 = note[:text].encode(xml: :text)
    xml = <<~XML
      <sphinx:document id="#{@sphinx_doc_id}">
        <canon>#{@canon}</canon>
        <vol>#{@vol}</vol>
        <file>#{@sutra_no}</file>
        <work>#{@work_id}</work>
        <juan>#{juan}</juan>
        <lb>#{note[:lb]}</lb>
        <n>#{n}</n>
        <content>#{s1}</content>
    XML

    @work_info.each_pair do |k,v|
      xml += "<#{k}>#{v}</#{k}>\n"
    end

    xml += "</sphinx:document>\n"
    @footnotes.puts xml
  end

end