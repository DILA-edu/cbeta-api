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
  LOG = Rails.root.join('log', 'import-layers-log.htm')

  PUNCS = /
  [
    \n\r
    ,\.\(\)\[\]\x20
    。．，、；？！：（）「」『』《》＜＞〈〉〔〕［］【】〖〗…—　▆■□○―→←
  ]
  /x

  def initialize
    @layers = Rails.root.join('data-static', 'layers')
    @html_base = Rails.root.join('data', 'html')
    @out_base = Rails.root.join('data', 'html-with-layers')
    @xml_base = Rails.application.config.cbeta_xml

    FileUtils.rm_rf(@out_base)
    FileUtils.makedirs(@out_base)

    read_vars
    @gaijis = MyCbetaShare.get_cbeta_gaiji
  end

  def import(target_work)
    t1 = Time.now
    @target = target_work
    @count = { 'place' => 0, 'person' => 0 }
    @mismatch = 0
    @log = File.open(LOG, 'w')

    Dir.entries(@layers).each do |f|
      next if f.start_with? '.'
      @layer = f
      import_layer
    end

    if @mismatch == 0
      puts "成功，無差異。".colorize(:green)
      if @target.nil?
        puts "copy #{@out_base} => #{@html_base}"
        `cp -r #{@out_base}/* #{@html_base}`
      end
    else
      s = "文字不符筆數：#{@mismatch}\n"
      puts s.red
      puts "請查看 #{LOG}"
      @log.puts "<hr>\n"
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
      @mismatch += 1
      @log_buf[:dirty] = true
      @log_buf[:text] << <<~HTML
        <hr>
        mismatch: #{@mismatch}<br>
        名稱結束處文字不符<br>
        #{@work}<br>\n
        #{row.to_s}<br>
      HTML
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

    @log_buf[:text] << "check_start, name: #{name}, text: #{text}<br>\n"
    if text.size < name.size
      flag = check_start_str(name, text)
    else
      flag = check_start_str(text, name)
    end
    unless flag
      @mismatch += 1
      @log_buf[:dirty] = true
      @log_buf[:text] << <<~HTML
        <hr>
        mismatch: #{@mismatch}<br>
        名稱起始處文字不符
        #{@work}<br>
        #{row.to_s}<br>
      HTML
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
      @mismatch += 1
      @log_buf[:dirty] = true
      @log_buf[:text] << <<~MSG
        <hr>
        位置超出文字範圍<br>
        #{row.to_s}
      MSG
    end

    case row['type']
    when 'start'
      check_start(line_text, i-1, row)
    when 'end'
      check_end(line_text, i, row)
    else
      @mismatch += 1
      @log_buf[:dirty] = true
      @log_buf[:text] << <<~MSG
        <hr>
        mismatch: #{@mismatch}
        未知的 type: #{row['type']}
        key: #{row['key']}
      MSG
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
    @cbeta_lines[@lb] << r
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

    s.gsub!(PUNCS, '')
    @cbeta_lines[@lb] << s
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
    unless @target.nil?
      return unless @basename == @target
    end
    
    puts @basename
    read_cbeta_lines
    @current_juan = nil
    @html_doc = nil
    @html_fn = nil
    old_lb = nil
    puts "import file: #{fn}"
    CSV.foreach(fn, headers: true) do |row|
      next if row['lb'].start_with? 'f'

      begin
        work, juan = JuanLine.find_by_vol_lb(@vol, row['lb'])
      rescue => e
        puts '-' * 10
        puts e.message
        puts @basename
        abort row.to_s
      end

      unless juan == @current_juan
        save_html unless @current_juan.nil?
        fn = "%03d.html" % juan
        @html_fn = File.join(@html_base, @canon, work, fn)
        @html_out = File.join(@out_base, @canon, work, fn)
        abort "error #{__LINE__} 檔案不存在: #{@html_fn}" unless File.exist?(@html_fn)
        puts "read html file: #{@html_fn}"
        @html_doc = File.open(@html_fn) { |f| Nokogiri::HTML(f) }
        lb = @html_doc.at_xpath("//span[@class='lb']")
        @work = lb['id'].split('_').first
        @current_juan = juan
      end
      unless row['lb'] == old_lb
        old_lb = row['lb']
      end

      import_row(row)
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

    lb   = row['lb']
    type = row['type']
    tag  = row['tag']

    if type == 'start'
      @count[tag] += 1
      i = @count[tag]
      if (i % 100) == 0
        print "#{tag}: #{i}"        
        if @mismatch > 0
          puts ", mismatch: #{@mismatch}"
        else
          puts
        end
      end
    end

    @anchor = %(<a id="#{tag}_#{type}_#{@count[tag]}" class="#{tag}_#{type}" data-key="#{row['key']}"/>)
    @layer_pos = row['position'].to_i
    @line_text = ''
    id = "#{@work}_p#{lb}"

    start_lb = @html_doc.at_xpath("//span[@class='lb' and @id='#{id}']")
    if start_lb.nil?
      @mismatch += 1
      @log.puts "<hr>\n"
      @log.puts "mismatch: #{@mismatch}<br>\n"
      @log.puts "#{@work}<br>\n"
      @log.puts "[Line: #{__LINE__}] HTML 檔裡找不到 #{id}<br>"
      return
    end

    @log_buf = { dirty: false, text: '' }
    @log_buf[:text] << "<p>找到行號: #{start_lb}</p>"
    start_lb.xpath("./following::span[@class='t']").each do |node|
      if node['l'] > lb
        puts '-' * 20
        puts "發生錯誤, id: #{id}, 程式行號: #{__LINE__}" 
        puts %(lb: #{lb}, <span class="t" l="#{node['l']}">)
        puts row.to_s
        abort
      end
      @html_pos = node['w'].to_i - 1
      break if import_row_traverse(node)
    end

    @log.puts @log_buf[:text] if @log_buf[:dirty]
  end

  def import_row_traverse(node)
    @log_buf[:text] << "import_row_traverse, l: #{node['l']}, w: #{node['w']}\n"
    @log_buf[:text] << "<blockquote>\n"
    r = false
    node.children.each do |c| 
      next '' if c.comment?

      @log_buf[:text] << "layer_pos: #{@layer_pos}, html_pos: #{@html_pos}<br>\n"
      if @row['type'] == 'start' and @html_pos > @layer_pos
        check_text(@line_text, @row)
        c.add_previous_sibling(@anchor)
        r = true
        break
      end

      if c.name == 'a'
        next if %w[person_start person_end place_start place_end].include?(c['class'])
      end

      if c.name == 'span'
        next if %w[pc person_start person_end place_start place_end].include?(c['class'])
      end

      if c.name == 'a' and c['class'] == 'gaijiAnchor'
        if import_row_gaiji(c)
          r = true
          break
        else
          next
        end
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
    @log_buf[:text] << "</blockquote>\n"
    r
  end

  def import_row_gaiji(e)
    text = e.text
    i = @html_pos + text.size

    if i < @layer_pos
      @html_pos = i
      @line_text << text
      return false
    end

    @html_pos += 1
    check_text(@line_text, @row)
    if @row['type'] == 'start'
      e.add_previous_sibling(@anchor)
    else
      e.add_next_sibling(@anchor)
    end
    true
  end

  def import_row_text(e)
    text = e.text
    @log_buf[:text] << "import_row_text, text: #{text}<br>\n"
    i = @html_pos + text.size

    if i < @layer_pos
      @html_pos = i
      @line_text << text
      return false
    end

    @html_pos += 1
    if @layer_pos < @html_pos
      puts "[#{__LINE__}] html_pos 已超過 layer_pos"
      puts @basename
      puts @row.to_s
      abort 
    end
    i = @layer_pos - @html_pos
    i += 1 if @row['type'] == 'end' # 如果是結束標記，要放在文字後面
    s = text[0, i]
    if s.nil?
      puts "[Line: #{__LINE__}]"
      puts @row.to_s
      abort
    end
    @line_text << s
    check_text(@line_text, @row)
    s << @anchor
    s << text[i..-1] if text.size > i
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
          @vars[t] << ",#{line}"
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
