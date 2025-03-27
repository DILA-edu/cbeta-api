module P5aToHtmlShare

  def e_l(e, mode)
    return traverse(e, mode) if mode=='footnote'

    row = HTMLNode.new('div')
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

    node = HTMLNode.new('div')
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

  def remove_text_indent_from_style(style)
    a = style.split(';')
    a.delete_if { |s| s.start_with?('text-indent:') }
    a.join(';')
  end
end
