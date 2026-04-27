# frozen_string_literal: true

namespace :convert do
  task :xml4docx2, [:filter] => :environment do |t, args|
    dir1 = Rails.root.join('data', 'xml4docx1')
    dir2 = Rails.root.join('data', 'xml4docx')
    XMLForDocx2.new.convert(dir1, dir2, filter: args[:filter])
  end
end

require_relative '../html-node'

# seg 包 seg, 扁平化 處理
class XMLForDocx2
  def initialize
    fn = Rails.root.join('lib', 'tasks', 'xml4docx-styles.yaml')
    @predefined_styles = YAML.load_file(fn)
  end

  def convert(src, dest, filter: nil)
    @filter = filter
    
    @dest = Pathname.new(dest)
    @dest.rmtree
    @dest.mkpath

    time_start = Time.now
    Dir.glob("#{src}/**/*.xml", sort: true) do
      next if not @filter.nil? and not it.include?(@filter)
      do_file(it)
      @log.close if @log
    end
    puts "\n" + ElapsedTime.label(time_start)
  end

  private

  def add_style(style)
    return if @styles.include?(style)

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

  def before_write(doc)
    xml = doc.to_xml
    # 去除多餘的 lb
    xml.gsub!(/(<\/p>\n*)<lb\/>\n*/, '\1')

    # <p> 的前面 如果不是 換行 或 <item>, 就加 換行
    xml.gsub!(/(?<!\n| |\-\->|<item>)(<p[> ])/m, "\n\\1")

    # <p> 最後的 <lb/> 要移除
    xml.gsub!(/<lb\/>\s*<\/p>/m, '</p>')

    # 段落開頭的 "(" 要在 行號 之後
    # <p rend="inlinenote_p">(<!-- lb: 0388a16 -->
    xml.gsub!(/(<p rend="inlinenote_p">)\((<!-- lb: \S+ -->)/, '\1\2(')

    xml
  end

  def do_file(xml_path)
    a = xml_path.split('/')
    @rel_path = a[-3..-2].join('/')
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
    handle_footnote_p
    traverse(@doc.root)
    abort "仍有 seg 包 seg" if @doc.at_xpath('//seg/seg')
    remove_empty_p

    FileUtils.makedirs(dest_folder)
    dest = File.join(dest_folder, @xml_fn)
    xml = before_write(@doc)

    File.write(dest, xml)
  end

  def e_footnote(e)
    s = traverse(e)
    @log.puts "#{__LINE__} footnote: #{s}"
    @log.puts "#{__LINE__} parent: #{e.parent.name}"
    case e.parent.name
    when 'body'
      p = e.add_previous_sibling("<p></p>").first
      e.replace(p)
      p.add_child(e)
      @log.puts "#{__LINE__} footnote 直接出現在 body 下，包 p: #{p.to_xml}"
    when 'list'
      item = e.add_previous_sibling("<item></item>").first
      e.replace(item)
      p = item.add_child("<p></p>").first
      p.add_child(e)
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
  
  def inlinenote?(e)
    return false if e.nil?
    return false if e.name !='p'
    return false unless e.key?('rend')
    e['rend'].include?('inlinenote')
  end

  def e_p(e)
    @log.puts "#{@xml_fn} e_p"
    if e.at_xpath('p').nil?
      if inlinenote?(e) and e.text !~ /^\(/
        s = +''
        s << '(' unless inlinenote?(e.previous_element)
        s << e.inner_html
        s << ')' unless inlinenote?(e.next_element)
        e.inner_html = s
      else
        traverse(e)
      end
      return
    end

    node = HTMLNode.new('p')

    rend = e['rend'] || ''
    r = +''
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
      add_style(rend)
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
    r = +''
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
      add_style(rend)
    end

    node['style'] = e['style'] if e.key?('style')
    node['style'] = c['style'] if c.key?('style') # 內層 style 優先
    node.content = c.inner_html
    node.to_s
  end

  def e_table(e)
    if e.key?('rend')
      rend = e['rend']
      add_style(rend)
    end
    traverse(e)
  end

  # 直接出現在 body 下的 (文字 或 footnote)，外面包 p
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
        unless %w[font footnote seg].include?(node.name)
          i += 1
          next
        end
      end

      p = node.add_previous_sibling("<p></p>\n").first
      p.add_child(node)
      @log.puts "#{__LINE__} 直接出現在 body 下，包 p: #{p.to_xml}"
      i += 1
    end
  end

  def handle_footnote_p
    @doc.root.xpath('//footnote').each do |e|
      paras = e.xpath('p')
      next if paras.size == 0 or paras.size > 1

      # 如果 footnote 下只有一個 p, 把 p 拿掉
      e.inner_html = paras.first.inner_html
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

  def remove_empty_p
    traverse(@doc.root)
    @doc.xpath('//p').each do |e|
      next if e.at_xpath('graphic')
      s = e.text.gsub(/\s/, '')
      if s.empty?
        e.add_previous_sibling(e.inner_html) # p 裡面可能有 lb
        e.remove
      end
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
      when 'table' then e_table(c)
      else
        traverse(c)
      end
    end
  end
end
