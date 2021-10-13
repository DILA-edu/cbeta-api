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
    @layers = Rails.root.join('data-static', 'layers')
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
    
    fn = Rails.root.join('log', 'import-layers-log.htm')
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
    @log.puts "check_text<br>"
    line_text = @cbeta_lines[row['lb']]
    i = row['position'].to_i
    if i > line_text.size
      @log.puts <<~MSG
        ----------
        位置超出文字範圍
        lb: #{lb2linehead(row['lb'])}
        位置: #{i}
        CBETA 文字: #{line_text}, 長度: #{line_text.size}
        #{row.to_s}
      MSG
      @mismatch += 1
      return
    end

    case row['type']
    when 'start'
      check_start(line_text, i-1, row)
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
    return if e.key?('type') and e['type'].match(/^cf\d+$/)
    traverse(e)
  end

  def handle_node(e)
    return '' if e.comment?
    return handle_text(e) if e.text?
    case e.name
    when 'mulu', 'rdg'
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
    puts @basename
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
    @row = row
    lb = row['lb']
    @anchor = %(<span class="#{row['tag']}_#{row['type']}" data-key="#{row['key']}"/>)
    @layer_pos = row['position'].to_i
    @log.puts "import_row, lb: #{lb}, position: #{@layer_pos}, tag: #{row['tag']}, type: #{row['type']}, key: #{row['key']}"
    @log.puts "<blockquote>"
    @line_text = ''
    @html_doc.xpath("//span[@class='t' and @l='#{lb}']").each do |node|
      @html_pos = node['w'].to_i
      break if import_row_traverse(node)
    end
    @log.puts "</blockquote>\n"
  end

  def import_row_traverse(node)
    @log.puts "<p>import_row_traverse, #{node.content}</p>"
    @log.puts "<blockquote>"
    r = false
    node.children.each do |c| 
      next '' if c.comment?
      @log.print "#{__LINE__} html position: #{@html_pos}"
      if c.text?
        @log.puts ", text node: #{c.text}<br>"
      else
        @log.puts ", tag: #{c.name}, class: #{c['class']}<br>"
      end

      if @row['type'] == 'start' and @html_pos > @layer_pos
        check_text(@line_text, @row)
        c.add_previous_sibling(@anchor)
        r = true
        break
      end

      if c.name == 'span'
        next if %w[pc person_start person_end place_start place_end].include?(c['class'])
      end

      if c.text?
        if import_row_text(c)
          r = true
          break
        end
      else
        if import_row_traverse(c)
          r = true
          break
        end
      end
    end
    @log.puts "</blockquote>"
    r
  end

  def import_row_text(e)
    text = e.text
    @log.puts "import_row_text, text: #{text}<br>"
    i = @html_pos + text.size
    @log.puts "i: #{i}<br>"

    if @row['type'] == 'start' and i <= @layer_pos
      @html_pos = i
      @line_text += text
      return false
    end

    if @row['type'] == 'end' and i < @layer_pos
      @html_pos = i
      @line_text += text
      return false
    end

    i = @layer_pos - @html_pos
    i += 1 if @row['type'] == 'end'
    s = text[0, i]
    @log.puts "#{__LINE__} #{s}<br>"
    @line_text += s
    check_text(@line_text, @row)
    @log.puts "#{__LINE__} #{text[i..-1]}<br>"
    s += @anchor
    s += text[i..-1] if text.size > i
    e.add_previous_sibling(s)
    e.remove
    true
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

    fn = Rails.root.join('lib/tasks/layers-ignore.txt')
    File.foreach(fn) do |line|
      line.chomp!
      line.split(",").each do |t|
        if @vars.key?(t)
          @vars[t] += ",#{line}"
        else
          @vars[t] = line
        end
      end
    end
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