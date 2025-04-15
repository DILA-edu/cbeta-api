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

# 產生 manticore 所需的 xml 檔案
class ManticoreNotes
  # 內容不輸出的元素
  PASS = %w[anchor back figDesc mulu pb rdg sic teiHeader]
  
  MISSING = '－'  # 某版用字缺的符號
  AROUND = 100 # 夾注前後文字數
  
  private_constant :PASS, :MISSING

  def initialize
    fn = Rails.root.join('log', 'manticore-notes.log')
    @log = File.open(fn, 'w')

    @xml_root = Rails.application.config.cbeta_xml
    @cbeta = CBETA.new
    @us = UnicodeService.new
    @gaijis = MyCbetaShare.get_cbeta_gaiji
    @gaijis_skt = MyCbetaShare.get_cbeta_gaiji_skt
    @dynasty_labels = read_dynasty_labels
    @cbs = CbetaString.new
  end

  def convert(target=nil)
    t1 = Time.now
    @stat = Hash.new(0)
    @sphinx_doc_id = 0

    fn = Rails.root.join('data', 'manticore-xml')
    FileUtils.makedirs(fn)
    fn = File.join(fn, 'notes.xml')
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
      夾注數量：#{@stat[:inline]}
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
    @in_inline = false
    @juan = 0
    @lg_row_open = false
    @mod_notes = Set.new
    @next_line_buf = ''
    @notes_mod    = {}
    @notes_orig   = {}
    @notes_add    = {}
    @notes_inline = {}
    @offset = 0

    @work_info = get_info_from_work(@work_id,
      exclude: [:alt, :byline, :juan_list, :juan_start, :work_type]
    )
    true
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
    @sutra_no = File.basename(xml_fn, ".xml")
    print "\nmanticore-notes.rb #{@sutra_no}"

    @work_id = CBETA.get_work_id_from_file_basename(@sutra_no)
    w = Work.find_by n: @work_id
    return if w.nil?

    t1 = Time.now
    before_parse_xml(xml_fn)
    return if @work_info.nil?
    @text = parse_xml(xml_fn)
    write_notes_for_manticore
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
    gid = e['ref'].delete_prefix('#')
    
    if gid.start_with? 'CB'
      g = @gaijis[gid]
    else
      g = @gaijis_skt[gid]
    end
    
    abort "Line:#{__LINE__} 無缺字資料:#{gid}" if g.nil?
    
    r = nil
    if gid.start_with?('SD')
      r = g['symbol'] || g['romanized']
    end

    r ||= @us.gaiji_unicode(g, normalize: @gaiji_norm.last)
    r ||= CBETA.pua(gid)
    @offset += r.size unless mode == 'footnote'
    r
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
      @notes_inline[@juan] = []
      print " #{@juan}"
    end
    ''
  end

  # 夾注裡可能有校注, 例： A091n1057_p0313a05
  #   這種情況，校注仍然要建 index document，但是不影響夾注的文字
  # 校注裡可能有夾注, 例： A097n1267_p0822b07
  def e_note(e, mode)
    return '' if e['rend'] == 'hide'
      
    if e.has_attribute?('type')
      t = e['type']
      case t
      when 'add'
        return e_note_add(e)
      when 'equivalent', 'rest'
        return ''
      when 'orig'
        return e_note_orig(e)
      when 'mod'
        return e_note_mod(e)
      when 'star'
        return ''
      else
        return '' if t.start_with?('cf')
      end
    end

    if e.key?('place')
      if "inline inline2 interlinear".include?(e['place'])
        return e_note_inline(e, mode)
      end
    end

    if e.has_attribute?('resp')
      return '' if e['resp'].start_with? 'CBETA'
    end

    log "不明的 note, lb: #{@lb}"

    return traverse(e, mode)
  end

  def e_note_add(e)
    n = @notes_add[@juan].size + 1
    n = "cb_note_#{n}"
    s = traverse(e, 'footnote')
    s << e_note_add_cf(e)
    @notes_add[@juan] << { lb: @lb, text: s }
    return ''
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

  def e_note_inline(e, mode)
    # 校注裡的夾注，不必建一個 index document
    if mode == 'footnote' or @in_inline
      s = traverse(e, mode)
      @offset += 2 unless mode == 'footnote'
      return "(#{s})"
    end

    note = { lb: @lb, offset: @offset }
    @in_inline = true
    s = traverse(e, mode)
    @in_inline = false

    note[:text] = s
    @notes_inline[@juan] << note
    @offset += 2
    "(#{s})"
  end

  def e_note_mod(e)
    s = traverse(e, 'footnote')
    n = e['n']
    @notes_mod[@juan][n] = { 
      lb: @lb, 
      text: s
    }

    ""
  end
  
  def e_note_orig(e)
    n = e['n']
    subtype = e['subtype']
    s = traverse(e, 'footnote')

    @notes_orig[@juan][n] = s
    @notes_mod[@juan][n] = { lb: @lb, text: s }
    
    return ''
  end
  
  def e_reg(e, mode)
    r = ''
    choice = e.at_xpath('ancestor::choice')
    r = traverse(e, mode) if choice.nil?
    r
  end

  def e_unclear(e, mode)
    r = traverse(e, mode)
    if r.empty?
      r = '▆'
      @offset += 1 unless mode == 'footnote'
    end
    r
  end  

  def handle_node(e, mode='text')
    return '' if e.comment?
    return handle_text(e, mode) if e.text?
    return '' if PASS.include?(e.name)

    norm_dirty = false
    if e.key?('behaviour') and e['behaviour']=="no-norm"
      @gaiji_norm.push false
      norm_dirty = true
    end

    puts e.name if e.name.include?('mulu')
    r = case e.name
    when 'app'       then e_app(e, mode)
    when 'g'         then e_g(e, mode)
    when 'lb'        then e_lb(e, mode)
    when 'lem'       then e_lem(e, mode)
    when 'note'      then e_note(e, mode)
    when 'milestone' then e_milestone(e)
    when 'reg'       then e_reg(e, mode)
    when 'unclear'   then e_unclear(e, mode)
    else traverse(e, mode)
    end

    @gaiji_norm.pop if norm_dirty
    r
  end
  
  def handle_text(e, mode)
    s = e.content().chomp
    return '' if s.empty?
    return '' if e.parent.name == 'app'

    # cbeta xml 文字之間會有多餘的換行
    s.gsub(/[\n\r]/, '')
    
    # 校注都不算 offset, 不管是否在夾注裡
    # 夾注也要算 offset, 如果在校注裡 就不算
    @offset += s.size unless mode == 'footnote'
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

  def write_notes_for_manticore
    all_notes = {}
    write_notes_mod(all_notes)
    write_notes_add(all_notes)
    write_notes_inline
    write_footnotes_for_download(all_notes)
  end

  def write_notes_add(all_notes)
    @notes_add.each_pair do |juan, notes|
      @stat[:add] += notes.size
      all_notes[juan] = [] unless all_notes.key?(juan)
      notes.each_with_index do |note, i|
        write_sphinx_doc(juan, note, n: "cb_note_#{i+1}")
        note[:n] = "A#{i+1}"
        all_notes[juan] << note
      end
    end
  end

  def write_notes_inline
    @notes_inline.each do |juan, notes|
      @stat[:inline] += notes.size
      notes.each do |note|
        write_sphinx_doc(juan, note, place: 'inline')
      end
    end
  end

  def write_notes_mod(all_notes)
    @notes_mod.each_pair do |juan, notes|
      @stat[:foot] += notes.size
      all_notes[juan] = []
      notes.each_pair do |n, note|
        write_sphinx_doc(juan, note, n: "n#{n}")
        note[:n] = n
        all_notes[juan] << note
      end
    end
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

  def write_sphinx_doc(juan, note, n: nil, place: 'foot')
    @sphinx_doc_id += 1
    xml = <<~XML
      <sphinx:document id="#{@sphinx_doc_id}">
        <note_place>#{place}</note_place>
        <canon>#{@canon}</canon>
        <canon_order>#{@canon_order}</canon_order>
        <vol>#{@vol}</vol>
        <file>#{@sutra_no}</file>
        <work>#{@work_id}</work>
        <juan>#{juan}</juan>
        <lb>#{note[:lb]}</lb>
    XML

    xml << "  <n>#{n}</n>\n" unless n.nil?

    if place == 'inline'
      xml << text_around_note(note)
    end

    # 去標點
    s = @cbs.remove_puncs(note[:text]).encode(xml: :text)
    xml << "  <content>#{s}</content>\n"

    # 含標點
    s = note[:text].encode(xml: :text)
    xml << "  <content_w_puncs>#{s}</content_w_puncs>\n"

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
    if s.nil?
      abort <<~MSG
        \nError manticore-notes.rb 行號: #{__LINE__}
        text size: #{@text.size}
        offset: #{i}
        note: #{note.inspect}
      MSG
    end
    s = s.encode(xml: :text)
    r = "  <prefix>#{s}</prefix>\n"

    i = note[:offset] + note[:text].size + 2
    s = @text[i, AROUND]
    if s.nil?
      abort <<~MSG
        \nError 行號: #{__LINE__}
        text size: #{@text.size}
        offset: #{i}
        note: #{note.inspect}
        text: ...#{@text[note[:offset], note[:text].size + 2]}
      MSG
    end

    text = @text[note[:offset], note[:text].size + 2]
    if text != "(#{note[:text]})"
      puts "\nlb: #{note[:lb]}"
      puts "note text: #{note[:text]}"
      puts "text: ...#{text}"
      abort "error #{__LINE__}"
    end

    s = s.encode(xml: :text)
    r + "  <suffix>#{s}</suffix>\n"
  end

  def log(msg)
    location = caller_locations.first
    file = File.basename(location.path)
    @log.puts "#{file}:#{location.lineno}, #{msg}"
  end

  include CbetaP5aShare
  include SphinxShare
end
