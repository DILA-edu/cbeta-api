# 讀取 CBETA XML P5a，匯入資料庫，每個版本一行一筆。
# CBETA版以及底本，還要有註解。
# 供 API 取得某個行號範圍的文字及註解。

require 'cbeta'
require 'json'
require 'pp'

class ImportLinesMultiEdition
  BLOCK_ELEMENTS = %w(byline cell head iterm juan l p)
  
  def initialize
    @cbeta = CBETA.new
    @xml_base = Rails.application.config.cbeta_xml
  end
  
  def import(arg)
    puts "import lines: #{arg}"
    if arg.nil?
      import_all
    elsif arg.size == 1
      import_canon(arg)
    elsif arg.match(/^[A-Z]\d{2,3}/)
      import_vol(arg)
    end
  end  
  
  private
  
  def add_cb_notes(n, s)
    @notes_cb[@lb] = {} unless @notes_cb.key? @lb
    @notes_cb[@lb][n] = s
    "<r w='【CBETA】'><a class='noteAnchor' href='#n#{n}'></a></r>"
  end  
  
  def before_traverse_xml(doc)
    @editions = get_editions(doc)
    @current_editions = [@editions]
    @notes_orig = {}
    @notes_cb = {}
    @mod_notes = Set.new
    read_mod_notes(doc)
  end
  
  def break_after(e)
    traverse(e) + '<br />'
  end
  
  def buf(s)
    @current_editions.last.each do |ed|
      @line_buf[ed][:html] += s
    end
  end  
  
  def get_editions(doc)
    r = Set.new [@orig, "【CBETA】"] # 至少有底本及 CBETA 兩個版本
    doc.xpath('//lem|//rdg').each do |e|
      w = e['wit'].scan(/【.*?】/)
      r.merge w
    end
    r
  end
  
  def handle_nodes(e)
    return '' if e.comment?
    return handle_text(e) if e.text?
    
    if BLOCK_ELEMENTS.include? e.name
      r = break_after(e)
    else
      r = case e.name
      when 'app'  then e_app(e)
      when 'corr' then e_corr(e)
      when 'lb'   then e_lb(e)
      when 'lem'  then e_lem(e)
      when 'note' then e_note(e)
      when 'rdg'  then e_rdg(e)
      when 'sic'  then e_sic(e)
      else traverse(e)
      end
    end
    r
  end
  
  def e_app(e)
    traverse(e)
  end
  
  def e_corr(e)
    s = traverse(e)
    "<r w='【CBETA】'>#{s}</r>"
  end
  
  def e_lb(e)
    @lb = e['n']
    "\n<lb n='#{@lb}'/>"
  end
  
  def e_lem(e)
    # 沒有 rdg 的版本，用字同 lem
    editions = Set.new @current_editions.last
    e.xpath('./following-sibling::rdg').each do |rdg|
      rdg['wit'].scan(/【.*?】/).each do |w|
        editions.delete w
      end
    end
    @current_editions << editions
    s = traverse(e)
    @current_editions.pop
    w = editions.to_a.join
    "<r w='#{w}'>#{s}</r>"
  end
  
  def e_note(e)
    n = e['n']
    if e.has_attribute?('type')
      t = e['type']
      case t
      when 'equivalent'
        return ''
      when 'orig'
        return e_note_orig(e)
      when 'orig_biao'
        return e_note_orig(e, 'biao')
      when 'orig_ke'
        return e_note_orig(e, 'ke')
      when 'mod'
        @notes_cb[@lb] = {} unless @notes_cb.key? @lb
        @notes_cb[@lb][n] = traverse(e)
        return "<r w='【CBETA】'><a class='noteAnchor' href='#n#{n}'></a></r>"
      when 'rest'
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
      return "<span class='doube-line-note'>#{r}</span>"
    else
      return traverse(e)
    end
  end

  def e_note_orig(e, anchor_type=nil)
    n = e['n']
    s = traverse(e)
    
    @notes_cb[@lb]   = {} unless @notes_cb.key? @lb
    @notes_orig[@lb] = {} unless @notes_orig.key? @lb
    
    @notes_orig[@lb][n] = s
    @notes_cb[@lb][n] = s

    label = case anchor_type
    when 'biao' then " data-label='標#{n[-2..-1]}'"
    when 'ke'   then " data-label='科#{n[-2..-1]}'"
    else ''
    end
    s = "<a class='noteAnchor' href='#n#{n}'#{label}></a>"
    r = "<r w='#{@orig}'>#{s}</r>"
    
    unless @mod_notes.include? n
      r += "<r w='【CBETA】'>#{s}</r>"
    end
    r
  end
  
  def e_rdg(e)
    editions = e['wit'].scan(/【.*?】/)
    w = editions.join
    s = traverse(e)
    "<r w='#{w}'>#{s}</r>"
  end
  
  def e_sic(e)
    s = traverse(e)
    editions = Set.new @editions
    editions.delete '【CBETA】'
    w = editions.to_a.join
    "<r w='#{w}'>#{s}</r>"
  end
  
  def import_all()
    Dir.entries(@xml_base).sort.each do |canon|
      next if canon.start_with? '.'
      next if canon=='schema'
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
    puts "import vol #{vol}"
    
    print "destroy old data in db..."
    Line.delete_all(vol: vol)
    puts "done"
    
    @canon = vol[0]
    @vol = vol
    @orig = @cbeta.get_canon_symbol(@canon)
    @orig_short = @orig.sub(/^【(.*)】$/, '\1')
    
    folder = File.join(@xml_base, @canon, vol)
    Dir.entries(folder).sort.each do |f|
      next unless f.end_with? '.xml'
      p = File.join(folder, f)
      import_xml_file(p)
    end
  end
  
  def import_xml_file(fn)
    puts "import #{fn}"
    
    @work_id = File.basename(fn, ".xml")
    if @work_id.match(/^(T\d\dn0220).*$/)
      @work_id = $1
    end
    doc = open_xml(fn)
    before_traverse_xml(doc)
    root = doc.root()
    body = root.at_xpath("text/body")
    @lb = nil
    all_html = traverse(body)
    write(all_html)
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
      r += handle_nodes(c)
    }
    r
  end
  
  def write(html)
    if Rails.env.development?
      fn = File.join('/temp/cbeta-lines', "#{@work_id}.htm")
      File.write(fn, html)
    end
    
    @editions.each do |ed|
      frag = Nokogiri::HTML.fragment("<root>#{html}</root>")
      frag.search("r").each do |node|
        if node['w'].include? ed
          node.add_previous_sibling node.inner_html
        end
        node.remove
      end
      text = frag.to_html
      text.sub!(/^<root>(.*)<\/root>$/m, '\1')
      
      edition = ed.sub(/^【(.*)】$/, '\1')
      if edition != 'CBETA' and edition != @orig_short
        edition = @orig_short + '→' + edition
      end      
      
      puts "write edition: #{ed}"
      
      if Rails.env.development?
        fn = File.join('/temp/cbeta-lines', "#{@work_id}-#{edition}.htm")
        File.write(fn, text)
      end
      
      text.split("\n").each do |line|
        next if line.empty?
        data = { vol: @vol, edition: edition }
        line.match(/<lb n="(.*?)"><\/lb>(.*)$/) {
          lb = $1
          data[:html] = $2
          data[:linehead] = "#{@work_id}_p#{lb}"
          case edition
          when 'CBETA'
            data[:notes] = JSON.generate(@notes_cb[lb]) if @notes_cb.key? lb
          when @orig
            data[:notes] = JSON.generate(@notes_orig[lb]) if @notes_orig.key? lb
          end
        }
        Line.create data
      end
    end
  end
  
end