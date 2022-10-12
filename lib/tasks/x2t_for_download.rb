require 'cgi'
require 'date'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'set'
require 'yaml'
require 'zip'
require_relative 'share'
require_relative 'cbeta_p5a_share'

# Convert CBETA XML P5a to HTML
#
# CBETA XML P5a 可由此取得: https://github.com/cbeta-git/xml-p5a
#
# 轉檔規則請參考: http://wiki.ddbc.edu.tw/pages/CBETA_XML_P5a_轉_HTML
class P5aToTextForDownload
  # 內容不輸出的元素
  PASS=['anchor', 'back', 'teiHeader']

  # 某版用字缺的符號
  MISSING = '－'
  
  private_constant :PASS, :MISSING

  # @param params [Hash]
  #   :xml_root [String] 來源 CBETA XML P5a 路徑
  #   :out_root [String] 輸出 路徑
  def initialize(params)
    @params = params
    @format = 'text'
    @cbeta = CBETA.new
    @gaijis = MyCbetaShare.get_cbeta_gaiji
    @gaijis_skt = MyCbetaShare.get_cbeta_gaiji_skt
    @us = UnicodeService.new
    
    FileUtils.rm_rf    @params[:out_root]
    FileUtils::mkdir_p @params[:out_root]
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
    if arg.size == 1
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
    each_canon(@params[:xml_root]) do |c|
      handle_collection(c)
    end
  end

  def copyright(work, juan)
    orig = @cbeta.get_canon_nickname(@series)
    
    # 處理 卷跨冊
    if work=='L1557' 
      @title = '大方廣佛華嚴經疏鈔會本'
      if @vol=='L131' and juan==17
        v = '130-131'
      elsif @vol=='L132' and juan==34
        v = '131-132'
      elsif @vol=='L133' and juan==51
        v = '132-133'
      end
    elsif work=='X0714' and @vol=='X40'  and juan==3
      @title = '四分律含注戒本疏行宗記'
      v = '39-40'
    else
      v = @vol.sub(/^[A-Z]0*([^0].*)$/, '\1')
    end
    
    n = @sutra_no.sub(/^[A-Z]\d{2,3}n0*([^0].*)$/, '\1')
    r = "#%s\n" % ('-' * 70)
    r += "#【經文資訊】#{orig}第 #{v} 冊 No. #{n} #{@title}\n"
    r += "#【版本記錄】發行日期：#{@params[:publish]}，最後更新：#{@updated_at}\n"
    r += "#【編輯說明】本資料庫由中華電子佛典協會（CBETA）依#{orig}所編輯\n"
    r += "#【原始資料】#{@contributors}\n"
    r += "#【其他事項】本資料庫可自由免費流通，詳細內容請參閱【中華電子佛典協會資料庫版權宣告】\n"
    r += "#%s\n\n" % ('-' * 70)
    r
  end
  
  def e_caesura(e)
    i = 2
    
    if e.key?('style')
      e['style'].match(/text-indent:(\d+)em/) do
        i = $1.to_i
      end
    end

    return '　' * i
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
    
    if gid.start_with?('SD') or gid.start_with?('RJ')
      return g['symbol'] if g.key? 'symbol'
      return g['romanized'] unless g['romanized'].blank?
      return "◇"
    end
    
    return g['uni_char'] if @us.level2?(g['unicode']) # 直接採用 unicode
    
    if @gaiji_norm.last
      return g['norm_uni_char'] if @us.level2?(g['norm_unicode'])
      return g['norm_big5_char'] unless g['norm_big5_char'].blank?
    end

    zzs = g['composition']
    abort "缺組字式：#{gid}" if zzs.nil?

    return zzs
  end

  def e_graphic(e)
    url = File.basename(e['url'])
    src = File.join(Rails.configuration.x.figures, @series, url)
    
    dest = File.join(@params[:out_root], @series, @work_id)
    FileUtils.mkdir_p dest
    FileUtils.cp src, dest
    
    j = "#{@work_id}_%03d" % @juan
    dest = File.join(@params[:out_root], @series, j)
    FileUtils.mkdir_p dest
    FileUtils.cp src, dest
    
    "【圖：#{url}】"
  end

  def e_item(e)
    s = traverse(e)
    
    if e.key? 'n'
      s = e['n'] + s
    end
    
    s + "\n"
  end
  
  def e_l(e)
    if @lg_type == 'abnormal'
      return traverse(e)
    end
    
    traverse(e) + "\n"
  end
  
  def e_lb(e)
    return "\n" if @lb_break.last
    ''
  end

  def e_milestone(e)
    r = ''
    if e['unit'] == 'juan'
      @juan = e['n'].to_i
      ele_milestone_juan
      r += "<juan #{@juan}>"
    end
    r
  end

  def e_mulu(e)
    return '' if e['type'] == '卷'
    i = e['level'].to_i - 1
    @toc << '  ' * i + e.text + "\n"
    ''
  end
  
  def e_p(e)
    if e['type'] == 'pre'
      @lb_break << true
    else
      @lb_break << false
    end
    r = traverse(e) + "\n\n"
    r += write_block_notes
    @lb_break.pop
    r
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

  def e_unclear(e)
    ele_unclear(e)
  end

  def handle_collection(c)
    @series = c
    $stderr.puts "x2t_for_download #{c}, notes: #{@params[:notes]}"
    folder = File.join(@params[:xml_root], @series)
    Dir.entries(folder).sort.each { |vol|
      next if ['.', '..', '.DS_Store'].include? vol
      handle_vol(vol)
    }
    zip_by_work(@series)
  end

  def handle_node(e)
    return '' if e.comment?
    return handle_text(e) if e.text?
    
    return '' if PASS.include?(e.name)
    return '' if %w(rdg sic).include? e.name
    
    if %w(byline figure head juan lg list table).include? e.name
      r = traverse(e) + "\n"
      r << "\n" unless e.name == 'lg'
      return r + write_block_notes
    end
    
    if %w(cell docNumber row).include? e.name
      return traverse(e) + "\n"
    end
    
    r = case e.name
    when 'app'       then ele_app(e)
    when 'caesura'   then e_caesura(e)
    when 'foreign'   then e_foreign(e)
    when 'g'         then e_g(e)
    when 'graphic'   then e_graphic(e)
    when 'item'      then e_item(e)
    when 'l'         then e_l(e)
    when 'lb'        then e_lb(e)
    when 'note'      then ele_note(e, 'text')
    when 'milestone' then e_milestone(e)
    when 'mulu'      then e_mulu(e)
    when 'p'         then e_p(e)
    when 'reg'       then e_reg(e)
    when 'sg'        then e_sg(e)
    when 't'         then e_t(e)
    when 'term'      then e_term(e)
    when 'text'      then e_text(e)
    when 'tt'        then e_tt(e)
    when 'unclear'   then e_unclear(e)
    else traverse(e)
    end
    r
  end

  def handle_sutra(xml_fn)
    @back = { 0 => '' }
    @dila_note = 0
    @gaiji_norm = [true]
    @in_l = false
    @juan = 0
    @lb_break = [false]
    @lg_row_open = false
    @next_line_buf = ''
    @open_divs = []
    @sutra_no = File.basename(xml_fn, ".xml")
    @toc = ''
    @work_id = CBETA.get_work_id_from_file_basename(@sutra_no)
    $stderr.puts "x2t_for_download #{@work_id}, notes: #{@params[:notes]}"
    @updated_at = MyCbetaShare::get_update_date(xml_fn)
    
    if @sutra_no.match(/^(T05|T06|T07)n0220/)
      @sutra_no = "#{$1}n0220"
    end    
    
    text = parse_xml(xml_fn)
    write_juans(text)
    write_toc
  end

  def handle_text(e)
    s = e.content().chomp
    return '' if s.empty?
    return '' if e.parent.name == 'app'

    # cbeta xml 文字之間會有多餘的換行
    s.gsub(/[\n\r]/, '')
  end
  
  def handle_vol(vol)
    $stderr.puts "x2t_for_download #{vol}"
    canon = CBETA.get_canon_from_vol(vol)
    @orig = @cbeta.get_canon_abbr(canon)
    abort "未處理底本" if @orig.nil?

    @vol = vol
    @series = CBETA.get_canon_from_vol(vol)
    
    source = File.join(@params[:xml_root], @series, vol)
    Dir[source+"/*"].each { |f|
      handle_sutra(f)
    }
    puts
  end

  def handle_vols(v1, v2)
    puts "convert volumns: #{v1}..#{v2}"
    @series = CBETA.get_canon_from_vol(v1)
    folder = File.join(@params[:xml_root], @series)
    Dir.foreach(folder) { |vol|
      next if vol < v1
      next if vol > v2
      handle_vol(vol)
    }
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

    if @params[:notes]
      @mod_notes = Set.new
      @notes_add = {}
      @notes_mod = {}
      @note_star_count = Hash.new(0)
      @block_notes = []
    end

    doc = open_xml(xml_fn)

    read_mod_notes(doc) if @params[:notes]
    write_work_yaml(doc)

    root = doc.root()
    text_node = root.at_xpath("text")
    @pass = [true]

    text = handle_node(text_node)
    text
  end

  def traverse(e, mode=nil)
    r = ''
    e.children.each { |c| 
      s = handle_node(c)
      r += s
    }
    r
  end

  def write_block_notes
    return '' unless @params[:notes]
    return '' if @block_notes.empty?

    r = @block_notes.join("\n    ")
    @block_notes = []
    '    ' + r + "\n\n"
  end
  
  def write_juan(juan_no, body)
    fn = "#{@work_id}_%03d.txt" % juan_no
    text = copyright(@work_id, juan_no) + body
    
    dest = File.join(@params[:out_root], @series, @work_id)
    FileUtils.mkdir_p dest
    dest = File.join(dest, fn)
    File.write(dest, text)
    
    if @params.key?(:out2)
      dest = File.join(@params[:out2], @series, @work_id)
      FileUtils.mkdir_p dest
      dest = File.join(dest, fn)
      File.write(dest, text)
    end
    
    j = "#{@work_id}_%03d" % juan_no
    dest = File.join(@params[:out_root], @series, j)
    FileUtils.mkdir_p dest
    dest = File.join(dest, fn)
    File.write(dest, text)
  end

  def write_juans(text)
    juans = text.split(/(<juan \d+>)/)
    juan_no = nil
    buf = ''

    # 一卷一檔
    juans.each do |j|
      if j =~ /<juan (\d+)>$/
        juan_no = $1.to_i
      elsif juan_no.nil?
        buf = j
      else
        write_juan(juan_no, buf+j)
      end
    end
  end

  def write_toc
    fn = "#{@work_id}-toc.txt"
    
    dest = File.join(@params[:out_root], @series, @work_id, fn)
    File.write(dest, @toc)
  end

  def write_work_yaml(doc)
    e = doc.xpath("//titleStmt/title")[0]
    @title = traverse(e)
    @title = @title.split()[-1]
    
    e = doc.at_xpath("//projectDesc/p[@lang='zh-Hant']")
    abort "找不到貢獻者" if e.nil?
    @contributors = e.text

    e = doc.at_xpath("//sourceDesc/bibl/title[@level='s' and@lang='zh-Hant']")
    abort "找不到 sourceDesc" if e.nil?
    @canon_name = e.text

    e = doc.at_xpath("//editorialDecl/punctuation")
    abort "找不到 punctuation" if e.nil?
    @punc = e.text

    h = {
      'id' => @work_id,
      'title' => @title,
      'source' => @canon_name,
      'publish_date' => @params[:publish],
      'last_modified' => Date.parse(@updated_at),
      'publisher' => '中華電子佛典協會（CBETA）',
      'contributors' => @contributors,
      'punctuation' => @punc,
      'license' => '本資料庫可自由免費流通，詳細內容請參閱 [中華電子佛典協會資料庫版權宣告](http://www.cbeta.org/copyright.php)'
    }
    
    fn = "#{@work_id}.yaml"
    text = h.to_yaml

    dest = File.join(@params[:out_root], @series, @work_id)
    FileUtils.mkdir_p dest
    path = File.join(dest, fn)
    File.write(path, text)

    if @params.key?(:out2)
      dest = File.join(@params[:out2], @series, @work_id)
      FileUtils.mkdir_p dest
      path = File.join(dest, fn)
      File.write(path, text)
    end
  end
  
  def zip_by_work(canon)
    canon_folder = File.join(@params[:out_root], @series)
    Dir.entries(canon_folder).each do |f|
      next if f.start_with? '.'
      folder = File.join(canon_folder, f)
      zipfile_name = File.join(@params[:out_root], "#{f}.txt.zip")
      Zip::File.open(zipfile_name, Zip::File::CREATE) do |zipfile|
        Dir.entries(folder).sort.each do |filename|
          next if filename.start_with? '.'
          # Two arguments:
          # - The name of the file as it will appear in the archive
          # - The original file, including the path to find it
          zipfile.add(filename, File.join(folder, filename))
        end
      end
      FileUtils.rm_rf folder
    end
    FileUtils.rm_rf canon_folder
  end
  
  include CbetaP5aShare
end
