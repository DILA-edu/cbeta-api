class XMLForDocx3
  def initialize
    fn = Rails.root.join('lib', 'tasks', 'xml4docx-styles.yaml')
    @styles = YAML.load_file(fn)

    fn = Rails.root.join('log', 'xml4docx3.log')
    @log = File.open(fn, 'w')

    rnc = Rails.root.join('data-static', 'schema', 'xml4docx.rnc')
    rng = Rails.root.join('data', 'xml4docx2', 'xml4docx.rng')
    abort unless system("trang #{rnc} #{rng}")
    @relaxng = Nokogiri::XML::RelaxNG(File.read(rng))
  end

  def check(src)
    puts "xml4docx3 檢查 XML 格式"
    Dir.glob("#{src}/**/*.xml", sort: true) do
      do_file(it)
    end
  end

  private

  def do_file(xml_path)
    print "\rxml4docx3 #{xml_path}  "

    doc = File.open(xml_path) { |f| Nokogiri::XML(f) }
    unless doc.errors.empty?
      abort "XML not well-form: #{doc.errors}"
    end

    errors = @relaxng.validate(doc)
    unless errors.empty?
      abort "\nXML not valid ❌"
    end

    traverse(doc.root)

    abort "仍有 seg 包 seg" if doc.at_xpath('//seg/seg')
  end

  def e_footnote(e)
    case e.parent.name
    when 'font'
      warn "footnote 在 font 裡面, text: #{e.text}, lb: #{$lb}"
    when 'cell', 'p', 'seg'
    else
      abort "footnote 不是在 p 裡面, parent: #{e.parent.name}, text: #{e.text}, lb: #{$lb}"
    end
  end

  def e_item(e)
    abort "item 下面沒有 p, lb: #{$lb}" if e.at_xpath('p').nil?
    traverse(e)
  end

  def e_seg(e)
    if e.key?('rend')
      rend = e['rend']
      if @styles[rend].nil?
        puts "seg rend: #{rend.inspect} 未定義" 
        puts $fn
        puts "text: #{e.text}"
        abort
      end
    end

    traverse(e)
  end

  def traverse(e)
    if e.text?
      s = e.text.gsub(/\s+/, '')
      return if s.empty?
      warn "文字直接出現在 body 下: #{e.text.inspect}" if e.parent.name == 'body'
      return
    end

    e.children.each do |c|
      if c.comment?
        $lb = c.text.sub(/lb: /, '')
      end
      case c.name
      when 'footnote' then e_footnote(c)
      when 'item' then e_item(c)
      when 'seg' then e_seg(c)
      else
        traverse(c)
      end
    end
  end

  def warn(msg)
    puts msg
    @log.puts msg
  end
end
