# seg 包 seg, 扁平化 處理

require_relative 'html-node'

class XMLForDocx2
  def initialize
    fn = Rails.root.join('lib', 'tasks', 'xml4docx-styles.yaml')
    @styles = YAML.load_file(fn)
  end

  def convert(src, dest)
    @dest = dest
    Dir.glob("#{src}/**/*.xml", sort: true) do
      do_file(it)
    end
  end
  
  def do_file(xml_path)
    a = xml_path.split('/')
    dest_folder = File.join(@dest, a[-4..-2].join('/'))
    @fn = a[-1]
    print "\rxml4docx2: #{@fn}  "

    doc = File.open(xml_path) { |f| Nokogiri::XML(f) }
    handle_body_text(doc)
    traverse(doc.root)

    abort "仍有 seg 包 seg" if doc.at_xpath('//seg/seg')

    FileUtils.makedirs(dest_folder)
    dest = File.join(dest_folder, @fn)
    File.write(dest, doc.to_xml)
  end

  def e_footnote(e)
    if e.parent.name == 'body' and e.next.name == 'p'
      e.next.prepend_child(e)
      return
    end
    traverse(e)
  end

  def e_item(e)
    # item 下面沒有 p, 加上 <p>
    unless e.at_xpath('p')
      if e.at_xpath('list')
        e.inner_html = e.inner_html.sub(/\A(.*?)(<list[ >].*)\z/m, '<p>\1</p>\2')
      else
        e.inner_html = "<p>#{e.inner_html}</p>"
      end
    end
    traverse(e)
  end

  def e_seg(e)
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
        node.copy_attributes(e)
        node.content = c.to_xml
        r << node.to_s
      end
    end
    e.add_previous_sibling (r)
    e.remove
  end

  def e_seg_seg(e, c)
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
      if @styles[rend].nil?
        puts "seg 包 seg, #{rend} 未定義" 
        puts @fn
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

  # 直接出現在 body 下的文字，移到後面的元素裡
  def handle_body_text(doc)
    body = doc.root.at_xpath('body')
    nodes = body.children

    i = 0
    while i < nodes.size
      unless nodes[i].text?
        i += 1
        next
      end

      a = Nokogiri::XML::NodeSet.new(doc)
      while nodes[i].text? or nodes[i].comment?
        a << nodes[i]
        i += 1
        break if i >= nodes.size
      end

      nodes[i].prepend_child(a)
    end
  end

  # &lt; 要維持 &lt;
  def handle_text(node)
    puts node.text if node.text.include?('&')
    node.text.encode(xml: :text)
  end

  def traverse(e)
    e.children.each do |c|
      case c.name
      when 'footnote' then e_footnote(c)
      when 'item' then e_item(c)
      when 'seg' then e_seg(c)
      else
        traverse(c)
      end
    end
  end

end
