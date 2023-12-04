# 讀取 CBETA XML P5a，匯入資料庫，每個版本一行一筆。
# CBETA版以及底本，還要有註解。
# 供 API 取得某個行號範圍的文字及註解。
#
# input:
#   * cbeta xml p5a
#   * cbeta metadata gaijis

require 'cbeta'
require 'json'
require 'pp'
require 'time_diff'
require_relative 'html-node'
require_relative 'cbeta_p5a_share'

class ImportLines
  BLOCK_ELEMENTS = %w(byline cell head iterm juan lg p)
  
  def initialize
    @cbeta = CBETA.new
    @xml_base = Rails.application.config.cbeta_xml
    @gaijis = CBETA::Gaiji.new
  end
  
  def import(arg)
    start_time = Time.now
    $stderr.puts "import lines: #{arg}"

    $stderr.puts "delete old data from table lines"
    if arg.nil?
      Line.delete_all
    else
      Line.where("linehead LIKE '#{arg}%'").delete_all
    end    
    
    if arg.nil?
      import_all
    elsif arg.size.between?(1,2)
      import_canon(arg)
    else
      import_vol(arg)
    end    
    
    $stderr.puts "花費時間：" + Time.diff(start_time, Time.now)[:diff]
  end
  
  private
  
  def add_cb_notes(n, s)
    @notes[@lb] = {} unless @notes.key? @lb
    @notes[@lb][n] = s
    %(<a class="noteAnchor" href="#n#{n}"></a>)
  end  
  
  def before_traverse_xml(doc)
    @gaiji_norm = [true]
    @next_line_buf = ''
    @notes = {}
    @mod_notes = Set.new
    read_mod_notes(doc)
  end
  
  def break_after(e)
    traverse(e) + '<br />'
  end
  
  def buf(s)
    @current_editions.last.each do |ed|
      @line_buf[ed][:html] << s
    end
  end  
    
  def e_anchor(e)
    return '◎' if e['type']=='circle'
    ''
  end
  
  def e_app(e)
    traverse(e)
  end
  
  def e_corr(e)
    traverse(e)
  end
  
  def e_foreign(e)
    return '' if e.key?('place') and e['place'].include?('foot')
    traverse(e)
  end
  
  def e_g(e)
    gid = e['ref'][1..-1]
    g = @gaijis[gid]
    abort "Line:#{__LINE__} 無缺字資料:#{gid}" if g.nil?
    
    if gid.start_with?('SD') or gid.start_with?('RJ')
      return g['symbol'] unless g['symbol'].blank?
      return g['romanized'] unless g['romanized'].blank?
      return "◇"
    end
   
    return g['uni_char'] unless g['uni_char'].blank?

    if @gaiji_norm.last
      return g['norm_uni_char'] unless g['norm_uni_char'].blank?
      return g['norm_big5_char'] unless g['norm_big5_char'].blank?
    end

    return g['composition'] unless g['composition'].blank?
    "[#{gid}]"
  end
  
  def e_lb(e)
    return '' if e['ed'] != @canon
    return '' if e['type'] == 'old'
    
    @lb = e['n']
    r = ''
    if e.parent.name == 'lg'
      r << '<br />'
    end
    
    r << "\n<lb n='#{@lb}'/><j#{$juan}>"
    
    unless @next_line_buf.empty?
      r << @next_line_buf
      @next_line_buf = ''
    end
    r
  end
  
  def e_lem(e)
    traverse(e)
  end

  def e_milestone(e)
    if e['unit'] == 'juan'
      $juan = e['n'].to_i
    end
    ''
  end
  
  def e_note(e)
    n = e['n']
    if e.has_attribute?('type')
      t = e['type']
      case t
      when 'add'        then return ''
      when 'equivalent' then return ''
      when 'orig'       then return e_note_orig(e)
      when 'mod'
        @notes[@lb] = {} unless @notes.key? @lb
        @notes[@lb][n] = traverse(e)
        return %(<a class="noteAnchor" href="#n#{n}"></a>)
      when 'rest'
        return ''
      else
        return '' if t.start_with?('cf')
      end
    end

    if e.has_attribute?('resp')
      return '' if e['resp'].start_with? 'CBETA'
    end

    if e.has_attribute?('place')
      if %w(inline inline2 interlinear).include? e['place']
        r = traverse(e)
        return "（#{r}）"
      end
    end
    
    return traverse(e)
  end

  def e_note_orig(e, anchor_type=nil)
    n = e['n']
    subtype = e['subtype']
    s = traverse(e)
    
    @notes[@lb]   = {} unless @notes.key? @lb
    @notes[@lb][n] = s

    label = case subtype
    when 'biao' then ' data-label="標%s"' % n[-2..-1]
    when 'jie'  then ' data-label="解%s"' % n[-2..-1]
    when 'ke'   then ' data-label="科%s"' % n[-2..-1]
    else ''
    end
    
    if @mod_notes.include? n
      r = ''
    else
      r = %(<a class="noteAnchor" href="#n#{n}"#{label}></a>)
    end
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
    @tt_type = e['type']
    traverse(e)
  end

  def handle_nodes(e)
    return '' if e.comment?
    return handle_text(e) if e.text?
    
    if BLOCK_ELEMENTS.include? e.name
      r = break_after(e)
    else
      r = case e.name
      when 'anchor'  then e_anchor(e)
      when 'app'     then e_app(e)
      when 'corr'    then e_corr(e)
      when 'foreign' then e_foreign(e)
      when 'graphic' then '【圖】'
      when 'g'       then e_g(e)
      when 'lb'      then e_lb(e)
      when 'lem'     then e_lem(e)
      when 'milestone' then e_milestone(e)
      when 'mulu'    then ''
      when 'note'    then e_note(e)
      when 'rdg'     then ''
      when 'sg'      then e_sg(e)
      when 'sic'     then ''
      when 't'       then e_t(e)
      when 'term'    then e_term(e)
      when 'text'    then e_text(e)
      when 'tt'      then e_tt(e)
      when 'unclear' then '▆'
      else traverse(e)
      end
    end
    r
  end
  
  def import_all()
    each_canon(@xml_base) do |canon|
      import_canon(canon)
    end
  end
  
  def import_canon(canon)
    folder = File.join(@xml_base, canon)
    Dir.entries(folder).sort.each do |v|
      next if v.start_with? '.'
      import_vol(v)
    end
  end
    
  def import_vol(vol)
    $stderr.puts "import_lines #{vol}"
    
    @canon = CBETA.get_canon_from_vol(vol)    
    @vol = vol
    @orig = @cbeta.get_canon_symbol(@canon)
    @orig_short = @orig.sub(/^【(.*)】$/, '\1')
    
    folder = File.join(@xml_base, @canon, vol)
    @inserts = []
    Dir.entries(folder).sort.each do |f|
      next unless f.end_with? '.xml'
      p = File.join(folder, f)
      import_xml_file(p)
    end
    
    sql = 'INSERT INTO lines ("linehead", "html", "notes", "juan")'
    sql << ' VALUES ' + @inserts.join(", ")
    ActiveRecord::Base.connection.execute(sql)
  end
  
  def import_xml_file(fn)
    @work_id = File.basename(fn, ".xml")
    if @work_id.match(/^(T\d\dn0220).*$/)
      @work_id = $1
    end
    doc = open_xml(fn)
    before_traverse_xml(doc)
    root = doc.root()
    text_node = root.at_xpath("text")
    @lb = nil
    all_html = handle_nodes(text_node)
    html_to_inserts(all_html)
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
  
  def handle_text(e)
    s = e.content().chomp
    return '' if s.empty?
    return '' if e.parent.name == 'app'

    # cbeta xml 文字之間會有多餘的換行
    s.gsub!(/[\n\r]/, '')
    
    # 把 & 轉為 &amp;
    CGI.escapeHTML(s)    
  end
  
  def traverse(e)
    r = ''
    e.children.each { |c| 
      r << handle_nodes(c)
    }
    r
  end
  
  def html_to_inserts(html)
    if Rails.env.development?
      # 把內容留下來 debug 用
      folder = File.join(Dir.home, 'temp', 'cbeta-lines')
      FileUtils.mkdir_p folder
      fn = File.join(folder, "#{@work_id}.htm")
      $stderr.puts "write #{fn}"
      File.write(fn, html)
    end
    
    html.split("\n").each do |line|
      next if line.empty?
      line.match(/<lb n='(.*?)'\/><j(\d+)>(.*)$/) {
        lb = $1
        juan = $2
        line_html = $3
        linehead = @work_id.clone
        linehead << '_' if @work_id.match?(/\d$/)
        linehead << "p#{lb}"
        notes = JSON.generate(@notes[lb]) if @notes.key? lb
        @inserts << "('#{linehead}', '#{line_html}', '#{notes}', #{juan})"
      }
    end
  end

  include CbetaP5aShare
end
