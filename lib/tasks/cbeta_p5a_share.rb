require 'cbeta'

module CbetaP5aShare
  def cbeta_copyright(canon, work, juan, publish, format: :html)
    args = {
      source_desc: @source_desc,
      canon: canon,
      canon_name: @canon_name,
      work: work,
      vol: @vol,
      juan: juan,
      title: @title,
      publish: publish,
      updated_at: @updated_at,
      contributors: @contributors,
      format:
    }
    MyCbetaShare.cbeta_juan_declare(args)
  end

  def each_canon(xml_root)
    Dir.entries(xml_root).sort.each do |c|
      next unless c.match(/^#{CBETA::CANON}$/)
      yield(c)
    end
  end

  def ele_app(e, mode=nil)
    if mode=='footnote' or not @params[:notes]
      lem = e.at('lem')
      return traverse(lem, mode)
    end
    
    r = ''
    if e['type'] == 'star'
      c = e['corresp'].delete_prefix('#')
      @note_star_count[c] += 1
      star_no = "#{c[-3..-1].to_i}-#{@note_star_count[c]}"
      if @format == 'text'
        s = @notes_mod[@juan][c]
        @block_notes << "[＊#{star_no}] #{s}"
        r = "[＊#{star_no}]"
      else
        r = "<a class='noteAnchor star' href='#n#{c}' data-star-no='#{star_no}'></a>"
      end
    end
    r + traverse(e)
  end

  def ele_lem_cf(e)
    cfs = []
    e.xpath('note').each do |c|
      next unless c.key?('type')
      next unless c['type'].match(/^cf\d+$/)
      s = traverse(c, 'footnote')
      if @format == 'html' and s.match(/^T\d{2,3}n.{5}p[a-z\d]\d{3}[a-z]\d\d$/)
        s = "<span class='cbeta-linehead'>#{s}</span>"
      end
      cfs << s
    end

    return '' if cfs.empty?

    s = cfs.join('; ')
    "(cf. #{s})"
  end

  def ele_milestone_juan
    return unless @params[:notes]
    @notes_mod[@juan] = {}
    @notes_add[@juan] = []
  end

  def ele_note(e, mode)
    return ele_note_in_foot(e) if mode == 'footnote'
    return '' if e['rend'] == 'hide'
      
    n = e['n']
    if e.has_attribute?('type')
      t = e['type']
      case t
      when 'equivalent' then return ''
      when 'rest'       then return ''
      when 'add'        then return ele_note_add(e, mode)
      when 'orig'       then return ele_note_orig(e, mode)
      when 'mod'        then return ele_note_mod(e, mode)
      when 'star'       then return ele_note_star(e, mode)
      else
        return '' if t.start_with?('cf')
      end
    end

    if e.has_attribute?('resp')
      return '' if e['resp'].start_with? 'CBETA'
    end

    r = traverse(e, mode)
    return r unless e.has_attribute?('place')
      
    c = case e['place']
    when 'interlinear'       then 'inline-note interlinear-note'
    when 'inline', 'inline2' then 'inline-note doube-line-note'
    else
      abort "未知的 note place 屬性：" + e['place']
    end
    
    if @format == 'text'
      "(#{r})"
    else
      "<small class='#{c}'>#{r}</small>"
    end
  end

  def ele_note_add(e, mode)
    return '' unless @params[:notes]

    n = @notes_add[@juan].size + 1
    s = traverse(e, 'footnote')
    s << ele_note_add_cf(e)

    if @format == 'html'
      n = "cb_note_#{n}"
      @notes_add[@juan] << "<span class='footnote add' id='#{n}'>#{s}</span>"
      node = HTMLNode.new('a')
      node['class'] = 'noteAnchor add'
      node['href'] = "##{n}"
      node['data-key'] = e['note_key'] if e.key?('note_key')
      return node.to_s
    else
      @notes_add[@juan] << "[A#{n}] #{s}"
      @block_notes << "[A#{n}] #{s}"
      return "[A#{n}]"
    end
  end

  def ele_note_add_cf(e)
    n = e['n']
    return '' if n.nil?

    app = e.next_sibling
    return '' if app.nil?
    return '' unless app.name == 'app'
    return '' unless app['n'] == n

    lem = app.at_xpath('lem')
    return '' if lem.nil?
    ele_lem_cf(lem)
  end

  def ele_note_mod(e, mode)
    return '' unless @params[:notes]

    n = e['n']
    s = traverse(e, 'footnote')
    @notes_mod[@juan][n] = s

    if @format == 'text'
      n = n[-3..-1].sub(/^0+/, '')
      @block_notes << "[#{n}] #{s}"
      return "[#{n}]"
    end

    node = HTMLNode.new('a')
    node['class'] = 'noteAnchor'
    node['href'] = "#n#{n}"
    node['data-key'] = e['note_key'] if e.key?('note_key')
    node.to_s + "\n"

    return node.to_s
  end

  def ele_note_orig(e, mode)
    return '' unless @params[:notes]

    n = e['n']

    # 如果 CBETA 沒有修訂，就跟底本的註一樣
    # 但是 CBETA 修訂後的編號，有時會加上 a, b
    # T01n0026, p. 506b07, 大正藏校勘 0506007, CBETA 拆為 0506007a, 0506007b
    return '' if @mod_notes.include?(n) or @mod_notes.include?(n+'a')

    subtype = e['subtype']
    s = traverse(e, 'footnote')
    @notes_mod[@juan][n] = s

    label = case subtype
    when 'biao' then " data-label='標#{n[-2..-1]}'"
    when 'jie'  then " data-label='解#{n[-2..-1]}'"
    when 'ke'   then " data-label='科#{n[-2..-1]}'"
    else ''
    end

    if @format == 'text'
      label = n[-3..-1].sub(/^0+/, '') if label.empty?
      @block_notes << "[#{label}] #{s}"
      return "[#{label}]"
    end
    
    "<a class='noteAnchor' href='#n#{n}'#{label}></a>"
  end

  def ele_note_star(e, mode)
    return '' unless @params[:notes]

    n = e['corresp'].delete_prefix('#')

    if @format == 'text'
      @block_notes << @notes_mod[@juan][n]
      return "[＊]"
    end

    href = "n#{n}"
    return "<a class='noteAnchor star' href='##{href}'></a>"
  end

  def ele_note_in_foot(e)
    return '' unless e.key?('place')
    if %w(interlinear inline inline2).include? e['place']
      return '(%s)' % traverse(e, 'footnote')
    else
      return ''
    end
  end

  def ele_unclear(e)
    r = traverse(e)
    r = '▆' if r.empty?
    if block_given?
      r = yield r
    end
    r
  end

  def get_source_desc(doc)
    e = doc.at_xpath("//idno[@type='CBETA']")
    abort "找不到 idno" if e.nil?
    id = e.text.strip

    e = doc.at_xpath("//sourceDesc/bibl/title[@level='s' and @lang='zh-Hant']")
    e = doc.at_xpath("//sourceDesc/bibl") if e.nil?
    abort "找不到來源說明" if e.nil?
    traverse(e)
  end

  def get_title(doc)
    e = doc.at_xpath("//titleStmt/title[@level='m']")
    r = traverse(e).split.last
    r.sub(/\(第\d+卷-第\d+卷\)$/, '')
  end

  def read_mod_notes(doc)
    doc.xpath("//note[@type='mod']").each do |e|
      n = e['n']
      @mod_notes << n

      # 例 T01n0026_p0506b07, 原註標為 7, CBETA 修訂為 7a, 7b
      n.match(/^(.*)[a-z]$/) { @mod_notes << $1 }
    end
  end
end
