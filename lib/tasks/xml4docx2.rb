# seg 包 seg, 扁平化 處理
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
    traverse(doc.root)

    abort "仍有 seg 包 seg" if doc.at_xpath('//seg/seg')

    FileUtils.makedirs(dest_folder)
    dest = File.join(dest_folder, @fn)
    File.write(dest, doc.to_xml)
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
    rend = e['rend']
    r = ''
    e.children.each do |c|
      if c.text?
        r << %(<seg rend="#{rend}">#{c.text}</seg>)
      elsif c.name == 'seg'
        if e['rend'] == rend
          rend2 = rend
        else
          rend2 = [rend, c['rend']].sort.join('_')
          if @styles[rend2].nil?
            puts "seg 包 seg, #{rend2} 未定義" 
            puts @fn
            puts "text: #{e.text}"
            abort
          end
        end
        r << %(<seg rend="#{rend2}">#{c.inner_html}</seg>)
      else
        r << %(<seg rend="#{rend}">#{c.to_xml}</seg>)
      end
    end
    e.add_previous_sibling (r)
    e.remove
  end

  def traverse(e)
    e.children.each do |c|
      case c.name
      when 'item' then e_item(c)
      when 'seg' then e_seg(c)
      else
        traverse(c)
      end
    end
  end

end
