# seg 包 seg, 扁平化 處理

require_relative 'html-node'

class XMLForDocx2
  def initialize
    fn = Rails.root.join('lib', 'tasks', 'xml4docx-styles.yaml')
    @predefined_styles = YAML.load_file(fn)
  end

  def convert(src, dest, filter: nil)
    @filter = filter
    @dest = dest
    time_start = Time.now
    Dir.glob("#{src}/**/*.xml", sort: true) do
      next if not @filter.nil? and not it.include?(@filter)
      do_file(it)
      @log.close if @log
    end
    puts "\n花費時間：" + ChronicDuration.output(Time.now - time_start)
  end

  private

  def add_style(style)
    styles_node = @doc.root.at_xpath('//settings/styles')
    css = @predefined_styles[style]
    styles_node.add_child("  <style name='#{style}'>#{css}</style>\n    ")
    @styles << style
  end
  
  def parse_xml(xml_path)
    text = File.read(xml_path)

    # 把 行號 移到 p, item 裡面
    regexp = /
      (
        (?:<!--\ lb:\ [^>]+\ -->)+
      )
      (
        (?:\s*<(?:item|list|p)(?:\ [^>]+?)?>)+
      )
    /x

    text.gsub!(regexp, '\2\1')
    fn = Rails.root.join('data', 'xml4docx1a', @rel_path, "#{@work}.xml")
    FileUtils.makedirs(File.dirname(fn))
    File.write(fn, text)

    Nokogiri::XML(text)
  end

  def do_file(xml_path)
    a = xml_path.split('/')
    @rel_path = a[-4..-2].join('/')
    dest_folder = File.join(@dest, @rel_path)
    @xml_fn = a[-1]
    print "\rxml4docx2: #{@xml_fn}  "

    @work = File.basename(@xml_fn, '.*')
    fn = Rails.root.join('log', 'xml4docx2', @rel_path, "#{@work}.log")
    FileUtils.makedirs(File.dirname(fn))
    @log = File.open(fn, 'w')

    @doc = parse_xml(xml_path)

    read_settings_styles
    handle_body_text
    handle_list_footnote
    traverse(@doc.root)
    abort "仍有 seg 包 seg" if @doc.at_xpath('//seg/seg')

    FileUtils.makedirs(dest_folder)
    dest = File.join(dest_folder, @xml_fn)
    xml = @doc.to_xml

    # <p> 的前面 如果不是 換行 或 <item>, 就加 換行
    xml.gsub!(/(?<!\n| |\-\->|<item>)(<p[> ])/m, "\n\\1")

    # <p> 最後的 <lb/> 要移除
    xml.gsub!(/<lb\/>\s*<\/p>/m, '</p>')
    File.write(dest, xml)
  end

  def e_footnote(e)
    return traverse(e) if e.parent.name != 'body'

    case e.next.name
    when 'list'
      move_to_list(e, e.next)
    when 'p'
      e.next.prepend_child(e)
    end
  end

  def move_to_list(nodes, list)
    item = list.at_xpath('item')
    abort "#{__LINE__} list 下無 item" if item.nil?

    p = item.at_xpath('p')
    if p.nil?
      item.prepend_child(nodes)
    else
      p.prepend_child(nodes)
    end
  end

  def e_item(e)
    return '' if e.children.empty?

    # item 下的文字，一律要包在 p 裡面
    if e.at_xpath('list | p')
      # T55n2154_p0611a05 item 下有文字夾在兩個 p 之間
      new_p = nil
      e.children.each do |c|
        if %w[list p].include?(c.name)
          new_p = nil
          next
        end

        if c.text? and c.text.match?(/\A\s+\z/m)
          c.remove if c == e.children.last
          next
        end
        new_p ||= c.add_previous_sibling("<p></p>").first
        new_p.add_child(c)
      end
    else
      e.inner_html = "<p>#{e.inner_html}</p>"
    end
    traverse(e)
  end

  def e_list(e)
    e.remove if e.children.empty?
    traverse(e)
  end

  def e_p(e)
    @log.puts "#{@xml_fn} e_p"
    if e.at_xpath('p').nil?
      if e['rend'] == 'inlinenote_p' and e.text !~ /^\(/
        e.inner_html = "(#{e.inner_html})"
      else
        traverse(e)
      end
      return
    end

    node = HTMLNode.new('p')

    rend = e['rend'] || ''
    r = ''
    e.children.each do |c|
      if c.text?
        node.copy_attributes(e)
        node.content = handle_text(c)
        r << node.to_s
      elsif c.name == 'p'
        r << handle_p_contain_p(e, c)
      else
        if c.comment?
          @log.puts "#{@xml_fn} #{c.content}" 
          r << c.to_xml
        else
          node.copy_attributes(e)
          node.content = c.to_xml
          r << node.to_s
        end
      end
    end
    node_set = e.add_previous_sibling (r)
    e.remove
    node_set.each { traverse(it) }
  end

  def handle_p_contain_p(e, c)
    @log.puts "#{@work} handle_p_contain_p"
    node = HTMLNode.new('p')

    rend1 = e['rend']
    rend2 = c['rend']

    rend = 
      if rend1 == rend2
        rend1
      else
        a = []
        a << rend1 if not rend1.nil? and not rend1.empty?
        a << rend2 if not rend2.nil? and not rend2.empty?
        a.sort.join('_')
      end

    if rend.nil? or rend.empty?
      node.attributes.delete('rend')
    else
      rend = 'byline' if rend == 'byline_juan'
      if @predefined_styles[rend].nil?
        puts "p 包 p, #{rend} 未定義" 
        puts @xml_fn
        puts "text: #{e.text}"
        abort
      end
      node['rend'] = rend
    end

    node['style'] = e['style'] if e.key?('style')
    node['style'] = c['style'] if c.key?('style') # 內層 style 優先
    node.content = c.inner_html
    node.to_s
  end

  def e_seg(e)
    @log.puts "e_seg, #{e.content}"
    return if e.at_xpath('seg').nil?

    node = HTMLNode.new('seg')

    rend = e['rend'] || ''
    r = ''
    e.children.each do |c|
      if c.text?
        node.copy_attributes(e)
        node.content = handle_text(c)
        r << node.to_s
      elsif c.name == 'seg'
        r << e_seg_seg(e, c)
      else
        @log.puts c.content if c.comment?
        node.copy_attributes(e)
        node.content = c.to_xml
        r << node.to_s
      end
    end
    e.add_previous_sibling (r)
    e.remove
  end

  def e_seg_seg(e, c)
    @log.puts "#{__LINE__} e_seg_seg, #{@xml_fn}, #{c.to_xml}"
    node = HTMLNode.new('seg')

    rend1 = e['rend']
    rend2 = c['rend']

    rend = 
      if rend1 == rend2
        rend1
      else
        a = []
        a << rend1 if not rend1.nil? and not rend1.empty?
        a << rend2 if not rend2.nil? and not rend2.empty?
        a.sort.join('_')
      end

    if rend.nil? or rend.empty?
      node.attributes.delete('rend')
    else
      if @predefined_styles[rend].nil?
        puts "seg 包 seg, #{rend} 未定義"
        puts @xml_fn
        puts "text: #{e.text}"
        abort
      end
      node['rend'] = rend
      add_style(rend) unless @styles.include?(rend)
    end

    node['style'] = e['style'] if e.key?('style')
    node['style'] = c['style'] if c.key?('style') # 內層 style 優先
    node.content = c.inner_html
    node.to_s
  end

  # 直接出現在 body 下的 (文字 或 footnote)，移到後面的元素裡
  def handle_body_text
    body = @doc.root.at_xpath('body')
    body_children = body.children

    i = 0
    while i < body_children.size
      node = body_children[i]
      if node.comment?
        i += 1
        next
      elsif node.text?
        if node.text.match?(/\A\s+\z/m)
          i += 1
          next
        end
      elsif node.element?
        unless %w[footnote seg].include?(node.name)
          i += 1
          next
        end
      end

      texts = Nokogiri::XML::NodeSet.new(@doc)
      while node.text? or node.comment? or %w[footnote seg].include?(node.name)
        texts << node
        i += 1
        break if i >= body_children.size
        node = body_children[i]
      end

      if i < body_children.size
        if node.name == 'list'
          move_to_list(texts, node)
        else
          node.prepend_child(texts)
        end
      else
        p = body.add_child('<p></p>').first
        p.add_child(texts)
      end
    end
  end

  # 處理 (直接出現在 list 下、夾在 item 之間的 footnote)
  # 移到下一個 item 裡開頭
  def handle_list_footnote
    @doc.root.xpath('//list/footnote').each do |footnote|
      node = footnote.next_element
      if node.name == 'item'
        node.prepend_child(footnote)
      end
    end
  end

  # &lt; 要維持 &lt;
  def handle_text(node)
    puts node.text if node.text.include?('&')
    node.text.encode(xml: :text)
  end

  def read_settings_styles
    @styles = Set.new
    @doc.root.xpath('//settings/styles/style').each do |s|
      @styles << s['name']
    end
  end

  def traverse(e)
    e.children.each do |c|
      @log.puts "#{@work} #{c.content}" if c.comment?
      case c.name
      when 'footnote' then e_footnote(c)
      when 'item' then e_item(c)
      when 'list' then e_list(c)
      when 'p' then e_p(c)
      when 'seg' then e_seg(c)
      else
        traverse(c)
      end
    end
  end
end
