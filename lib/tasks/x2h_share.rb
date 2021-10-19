module P5aToHtmlShare

  def e_l(e, mode)
    return traverse(e, mode) if mode=='footnote'

    row = HtmlNode.new('div')
    row['class'] = 'lg-row'

    content = traverse(e)
    if @lg_type == 'regular'
      row.content = e_l_regular_cells(content, e)
    else
      row.content = "<div class='lg-cell'>#{content}</div>\n"
    end

    spaces = ''
    if e.key?('style')
      if @lg_type == 'regular'
        s = remove_text_indent_from_style(e['style'])
        row['style'] = s unless s.empty?
      else
        row['style'] = e['style']
      end
    elsif @first_l and @lg_type != 'regular'
      # lg 的 text-indent 要放到第一個 cell
      parent = e.parent()
      if parent.has_attribute?('style')
        parent['style'].match(/text-indent: ?(-?\d+)em/) do |m|
          row['style'] = m[0]
          spaces = line_space(m[1].to_i)
        end
      end
    end
    @first_l = false

    spaces + row.to_s
  end

  def e_l_regular_cells(s, e)
    indent = nil
    spaces = nil
    if e.key?('style')
      e['style'].match(/text-indent: ?(-?\d+)em/) do |m|
        indent = $&
        spaces = line_space($1)
      end
    end

    # 如果第一個 <l> 未指定 text-indent, 就由 lg 繼承
    if indent.nil? and @first_l
      lg = e.parent
      if lg.key?('style')
        lg['style'].match(/text-indent: ?(-?\d+)em/) do |m|
          indent = $&
          spaces = line_space($1)
        end
      end
    end

    a = s.split(/(<caesura[^>]*?\/>)/)
    r = ''
    a.each_with_index do |v, i|
      next if v.start_with?('<caesura')
      
      if i == 0
        if indent.nil?
          r += "<div class='lg-cell'>#{v}</div>\n"
        else
          r += "#{spaces}<div class='lg-cell' style='#{indent}'>#{v}</div>\n"
        end
        next
      end

      caesura = a[i-1]
      if caesura.match(/<caesura ([^>]*?)\/>/)
        if caesura.match(/text\-indent: ?(\-?\d+)em/)
          s = line_space($1)
        else
          s = ''
        end
        r += "#{s}<div class='lg-cell' #{$1}>#{v}</div>\n"
      else
        r += "<div class='lg-cell'>#{v}</div>\n"
      end
    end
    r
  end

  def e_lg(e, mode)
    return traverse(e, mode) if mode=='footnote'

    @lg_type = e['type']

    r = ''

    head = e.at_xpath('head')
    unless head.nil?
      r += handle_node(head, mode)
    end

    node = HtmlNode.new('div')
    classes = ['lg']
    classes << e['rend'] if e.key? 'rend'
    classes << e['type'] if e.key? 'type'
    classes << e['subtype'] if e.key? 'subtype'
    node['class'] = classes.join(' ')

    if e.key?('style')
      s = e['style'].gsub(/text-indent:[^;]*/, '')
      node['style'] = s unless s.empty?
    end

    @first_l = true
    s = ''
    e.children.each do |c|
      s += handle_node(c, mode) unless c.name == 'head'
    end
    
    node.content = s

    # 注意 lg 前不能換行，否則 UI 會多空半格
    r + node.to_s
  end

  def html_copyright(work, juan)
    r = "<div id='cbeta-copyright'><p>\n"
    
    #orig = @cbeta.get_canon_nickname(@series)
    
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
    r += "【經文資訊】《#{@canon_name}》第 #{v} 冊 No. #{n} #{@title}<br/>\n"
    r += "【版本記錄】發行日期：#{@publish_date}，最後更新：#{@updated_at}<br/>\n"
    r += "【編輯說明】本資料庫由中華電子佛典協會（CBETA）依《#{@canon_name}》所編輯<br/>\n"
    
    r += "【原始資料】#{@contributors}<br/>\n"
    r += "【其他事項】詳細說明請參閱【<a href='http://www.cbeta.org/copyright.php' target='_blank'>中華電子佛典協會資料庫版權宣告</a>】\n"
    r += "</p></div><!-- end of cbeta-copyright -->\n"  
  end
  
  def read_canon_name
    fn = File.join(Rails.application.config.cbeta_data, 'canons.csv')
    r = {}
    CSV.foreach(fn, headers: true) do |row|
      r[row['id']] = row['name']
    end
    r
  end

  def remove_text_indent_from_style(style)
    a = style.split(';')
    a.delete_if { |s| s.start_with?('text-indent:') }
    a.join(';')
  end

end