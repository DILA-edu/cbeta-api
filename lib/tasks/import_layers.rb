require 'csv'
require 'colorize'
require_relative 'share'

# Prerequisites:
#   * GitHub: CBETA 缺字資料, 異體字資料
#   * HTML for UI
#   * Model: JuanLine
class ImportLayers
  TERM_NOR = {
  #  '女蝸' => '女媧',
  #  '滄洲' => '滄州'
  }
  def initialize
    @layers = Rails.root.join('data', 'layers')
    @html_base = Rails.root.join('data', 'html')
    @out_base = Rails.root.join('data', 'html-with-layers')
    @xml_base = Rails.application.config.cbeta_xml
    FileUtils.makedirs(@out_base)

    read_vars
    @gaijis = MyCbetaShare.get_cbeta_gaiji
  end

  def import()
    t1 = Time.now
    @count = { 'place' => 0, 'person' => 0 }
    @mismatch = 0
    
    fn = Rails.root.join('log', 'import_layers.log')
    @log = File.open(fn, 'w')

    Dir.entries(@layers).each do |f|
      next if f.start_with? '.'
      @layer = f
      import_layer
    end

    if @mismatch == 0
      puts "成功，無差異。".colorize(:green)
      puts "copy #{@out_base} => #{@html_base}"
      `cp -r #{@out_base}/* #{@html_base}`
    else
      s = "文字不符筆數：#{@mismatch}\n"
      puts s.red
      puts "請查看 log/import_layers.log"
      @log.puts '-' * 10
      @log.puts s
    end
    @log.close
    puts @count
    puts "花費時間：" + ChronicDuration.output(Time.now - t1)
  rescue CbetaError => e
    puts "Error code: #{e.code}"
    abort e.message
  end

  private

  def check_end(line_text, pos, row)
    # 取得該行 指定位置 前的文字
    text = line_text[0, pos]
    name = row['name']

    # 如果文字比較長，只取跟「名稱」相同長度的文字
    if text.size > name.size
      i = 0 - name.size
      text = text[i..-1]
    end

    # 比對時忽略異體字差異，所以先將異體字正規化
    name = TERM_NOR[name] if TERM_NOR.key?(name)

    if text.size < name.size
      flag = check_end_str(name, text)
    else
      flag = check_end_str(text, name)
    end

    unless flag
      @log.puts '-' * 10
      @log.puts "名稱結束處文字不符"
      @log.puts "lb: #{lb2linehead(row['lb'])}"
      @log.puts "CBETA 整行: #{line_text}"
      @log.puts "佛寺志位置: #{pos}"
      @log.puts "CBETA 文字: #{text}"
      @log.puts "佛寺志 文字: #{name}"
      @mismatch += 1
    end
  end

  def check_end_str(s1, s2)
    return true if s1.end_with?(s2)
    (1..s2.size).each do |i|
      next if check_var(s1[-i], s2[-i])
      return false
    end
    true
  end

  def check_start(line_text, pos, row)
    name = row['name']
    text = line_text[pos, name.size]
    name = name[0, text.size]

    name = TERM_NOR[name] if TERM_NOR.key?(name)

    if text.size < name.size
      flag = check_start_str(name, text)
    else
      flag = check_start_str(text, name)
    end
    unless flag
      msg = <<~MSG
        ----------
        名稱起始處文字不符
        lb: #{lb2linehead(row['lb'])}
        CBETA 整行: #{line_text}
        佛寺志位置: #{pos}
        CBETA 文字: #{text}
        佛寺志 文字: #{name}
      MSG
      @log.puts msg
      puts msg
      @mismatch += 1
    end
  end

  def check_start_str(s1, s2)
    return true if s1.start_with?(s2)
    (0..s2.size-1).each do |i|
      next if check_var(s1[i], s2[i])
      return false
    end
    true
  end

  def check_text(line_text, row)
    line_text = @cbeta_lines[row['lb']]
    i = row['position'].to_i
    if i > line_text.size
      @log.puts <<~MSG
        ----------
        位置超出文字範圍
        Layer: #{@layer}
        位置: #{i}
        CBETA 文字: #{line_text}, 長度: #{line_text.size}
        #{row.to_s}
      MSG
      @mismatch += 1
      return
    end

    case row['type']
    when 'start'
      check_start(line_text, i, row)
    when 'end'
      check_end(line_text, i, row)
    else
      @log.puts '-' * 10
      @log.puts "未知的 type: #{row['type']}"
      @log.puts "key: #{row['key']}"
      @mismatch += 1
    end
  end

  def check_var(c1, c2)
    return true if c1 == c2
    return false unless @vars.key?(c1)
    vars = @vars[c1].gsub(/CB\d+/) do
      CBETA.pua($&)
    end
    vars.include?(c2)
  end

  def e_app(e)
    case @canon
    when 'GA'
      w = '【志彙】'
    when 'GB'
      w = '【志叢】'
    else
      return traverse(e)
    end

    rdg = e.at_xpath("rdg[@wit='#{w}']")
    if rdg.nil?
      traverse(e)
    else
      traverse(rdg)
    end
  end

  def e_g(e)
    id = e['ref'].sub(/^#/, '')
    r = '●'
    if @gaijis.key? id
      g = @gaijis[id]
      if g.key? 'uni_char'
        r = g['uni_char']
      elsif g.key? 'norm_uni_char'
        r = g['norm_uni_char']
      elsif g.key? 'norm_big5_char'
        r = g['norm_big5_char']
      end
    end
    @cbeta_lines[@lb] += r
  end

  def e_lb(e)
    @lb = e['n']
    @cbeta_lines[@lb] = ''
  end

  def e_note(e)
    return if e['type'] == 'add'
    return if e['type'] == 'orig'
    traverse(e)
  end

  def handle_node(e)
    return '' if e.comment?
    return handle_text(e) if e.text?
    case e.name
    when 'mulu', 'rdg'
    when 'app'  then e_app(e)
    when 'g'    then e_g(e)
    when 'lb'   then e_lb(e)
    when 'note' then e_note(e)
    else traverse(e)
    end
  end

  def handle_text(e)
    return if @lb.nil?
    s = e.content().chomp
    return '' if s.empty?
    return '' if e.parent.name == 'app'

    # cbeta xml 文字之間會有多餘的換行
    s.gsub!(/[\n\r]/, '')
    s.gsub!(/[,\.\(\)\[\] 。．，、；？！：（）「」『』《》＜＞〈〉〔〕［］【】〖〗…—　▆■□○―]/, '')
    @cbeta_lines[@lb] += s
  end

  def import_canon(parent_folder)
    puts "canon: #{@canon}"
    folder = File.join(parent_folder, @canon)
    Dir.entries(folder).sort.each do |f|
      next if f.start_with? '.'
      @vol = f
      path = File.join(folder, f)
      import_vol(path)
    end
  end

  def import_file(fn)
    @basename = File.basename(fn, '.csv')
    read_cbeta_lines
    @current_juan = nil
    @html_doc = nil
    @html_fn = nil
    old_lb = nil
    puts "import file: #{fn}"
    CSV.foreach(fn, headers: true) do |row|
      next if row['lb'].start_with? 'f'
      work, juan = JuanLine.find_by_vol_lb(@vol, row['lb'])
      unless juan == @current_juan
        save_html unless @current_juan.nil?
        fn = "%03d.html" % juan
        @html_fn = File.join(@html_base, @canon, work, fn)
        @html_out = File.join(@out_base, @canon, work, fn)
        abort "error #{__LINE__} 檔案不存在: #{@html_fn}" unless File.exist?(@html_fn)
        puts "read html file: #{@html_fn}"
        @html_doc = File.open(@html_fn) { |f| Nokogiri::HTML(f) }
        @current_juan = juan
      end
      unless row['lb'] == old_lb
        old_lb = row['lb']
      end

      import_row(row)
      if row['type'] == 'start'
        t = row['tag']
        @count[t] += 1
        i = @count[t]
        if (i % 100) == 0
          puts "#{t}: #{i}"
        end
      end
    end
    save_html
  end

  def import_layer
    puts "layer: #{@layer}"
    folder = File.join(@layers, @layer)
    Dir.entries(folder).each do |f|
      next if f.start_with? '.'
      @canon = f
      import_canon(folder)
    end
  end

  def import_row(row)
    lb = row['lb']
    anchor = %(<span class="#{row['tag']}_#{row['type']}" data-key="#{row['key']}"/>)
    layer_pos = row['position'].to_i + 1
    line_text = ''
    @html_doc.xpath("//span[@class='t' and @l='#{lb}']").each do |node|
      html_pos = node['w'].to_i
      node.children.each do |c| 
        next '' if c.comment?
        if html_pos >= layer_pos
          check_text(line_text, row)
          c.add_previous_sibling(anchor)
          return
        end

        if c.name == 'span' and c['class'] == 'pc'
          next
        end

        if c.text?
          i = html_pos + c.text.size
          if row['type'] == 'start' and i <= layer_pos
            html_pos = i
            line_text += c.text
            next
          end

          if row['type'] == 'end' and i < layer_pos
            html_pos = i
            line_text += c.text
            next
          end

          i = layer_pos - html_pos
          s = c.text[0, i]
          line_text += s
          check_text(line_text, row)
          s += anchor + c.text[i..-1]
          c.add_previous_sibling(s)
          c.remove
          return
        end
      end
    end
  end

  def import_vol(folder)
    puts "vol: #{@vol}"
    Dir.entries(folder).sort.each do |f|
      next if f.start_with? '.'
      fn = File.join(folder, f)
      import_file(fn)
    end
  end

  def lb2linehead(lb)
    @basename + '_p' + lb
  end

  def read_cbeta_lines
    @cbeta_lines = {}
    @lb = nil
    fn = File.join(@xml_base, @canon, @vol, "#{@basename}.xml")
    puts "read #{fn}"
    doc = File.open(fn) { |f| Nokogiri::XML(f) }
    doc.remove_namespaces!
    traverse(doc.root)
  end

  def read_vars
    fn = File.join(Rails.configuration.cbeta_data, 'variants', 'vars-for-cbdata.json')
    @vars = JSON.parse(File.read(fn))
  end

  def save_html
    puts "write file #{@html_out}"
    FileUtils.makedirs(File.dirname(@html_out))
    File.write(@html_out, @html_doc.to_html)
  end

  def traverse(e)
    e.children.each { |c| 
      handle_node(c)
    }
  end
end