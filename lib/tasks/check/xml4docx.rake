namespace :check do
  task :xml4docx do
    dir = Rails.root.join('data', 'xml4docx2')
    CheckXMLForDocx.new.check(dir)
  end
end

# 檢查 xml4docx 檔案 是否正確
class CheckXMLForDocx
  def initialize
    fn = Rails.root.join('lib', 'tasks', 'xml4docx-styles.yaml')
    @styles = YAML.load_file(fn)

    fn = Rails.root.join('log', 'check_xml4docx.log')
    @log = File.open(fn, 'w')

    rnc = Rails.root.join('data-static', 'schema', 'xml4docx.rnc')
    rng = Rails.root.join('data', 'xml4docx2', 'xml4docx.rng')
    cmd = "trang #{rnc} #{rng}"
    puts cmd
    system(cmd)
    @relaxng = Nokogiri::XML::RelaxNG(File.read(rng))
  end

  def check(src)
    time_start = Time.now
    puts "check_xml4docx 檢查 XML 格式"
    @errors = []
    Dir.glob("#{src}/**/*.xml", sort: true) do
      do_file(it)
    end
    puts
    check_as_text('T/T0099/T0099_001.xml', /<p rend="標題">雜阿含經<\/p>/m)
    check_as_text('T/T0099/T0099_002.xml', /<p rend="license">【經文資訊】大正新脩大藏經 第 2 冊/m)
    check_as_text('T/T0220/T0220_201.xml', /<p rend="license">【經文資訊】大正新脩大藏經 第 6 冊/m)
    check_as_text('T/T0261/T0261_002.xml', /<\/footnote>\)<\/seg>娜岸<!-- lb: T08n0261_p0873c26 -->/m)
    check_as_text('T/T0262/T0262_007.xml', /伏遇.*<lb\/>.*亡夫/m)
    check_as_text('T/T0293/T0293_001.xml', /0661a04.*<footnote>.*0661a05/m)
    check_as_text('T/T0293/T0293_040.xml', /0851a17.*住持沙門如賢/m)
    check_as_text('T/T0299/T0299_002.xml', /0892c09.*?<footnote><font name="sidd">先<\/font>\(ra\)【大】，<font name="sidd">刑<\/font>\(re\)【宋】【元】【明】<\/footnote><font name="sidd">先<\/font><lb\/>\n?\(ra\).*?0892c10/m)

    check_as_text('T/T0860/T0860_001.xml', /「<font name="sidd">湡/m)    
    check_as_text('T/T0860/T0860_001.xml', /183b08.*<seg rend="corr"><font name="sidd">巧<\/font><\/seg><lb\/>\s*<seg rend="corr">\(na\)<\/seg>/m)

    check_as_text('T/T0864A/T0864A_001.xml', /0196a15.*部嚕唵.*0196a16/m)
    check_as_text('T/T0867/T0867_001.xml', /0254a29.*?怛.*?0254b02/m)
    check_as_text('T/T0868/T0868_002.xml', /0274b18.*』.*0274b19/m)
    check_as_text('T/T0956/T0956_001.xml', /0316a10.*\(此是梵本一字之呪\).*0316a11/m)
    check_as_text('T/T1096/T1096_001.xml', /0420c26.*0420c27/m)
    check_as_text('T/T1168B/T1168B_001.xml', /0676c16.*?<cell>如<lb\/>\n?<font name="sidd">珫<\/font><lb\/>\n?\(e\)<\/cell>.*?0676c18/m)
    check_as_text('T/T1299/T1299_001.xml', /虛室奎胃畢參鬼星翼角氐心<\/p>/m)
    check_as_text('T/T1299/T1299_001.xml', /0388a16.*\(新演如左.*0388a17/m)
    check_as_text('T/T1431/T1431_001.xml', /及法比丘僧，.*<lb\/>.*今演毘尼法/m)
    check_as_text('T/T2023/T2023_010.xml', /群生得光輝。<lb\/>\n?一萬八千土/m)    
    check_as_text('T/T2122/T2122_053.xml', /\(如四分律云/m)
    check_as_text('T/T2122/T2122_053.xml', /\(故佛本行經云/m)
    check_as_text('T/T2122/T2122_053.xml', /0683b02.*(?!\()爾時舍利弗.*0683b03/m)
    check_as_text('T/T2128/T2128_063.xml', /百一羯磨十卷.*0725a24/m)
    check_as_text('T/T2132/T2132_001.xml', /<font rend="corr" name="sidd">裶<\/font>/)

    check_as_text('T/T2133A/T2133A_001.xml', /<footnote>uparopara\?<\/footnote><font name="sidd">裶/)
    check_as_text('T/T2133A/T2133A_001.xml', /1190a22.*?<cell><font name="sidd">辱絞箌<\/font><lb\/>\n?\(sva\)\(rga\)<lb\/>\n?天<\/cell>.*?1190a24/m)
    check_as_text('T/T2133A/T2133A_001.xml', /1190b09.*?\(（？）\).*?1190b10/m)
    check_as_text('T/T2133A/T2133A_001.xml', /1194c17.*?<font name="sidd">巴<\/font>\(ṭa\)〔<font name="sidd">一<\/font>\(ka\)〕/m)
    
    check_as_text('T/T2149/T2149_005.xml', /0272b08.*0272b09/m)
    check_as_text('T/T2154/T2154_011.xml', /0592b06.*0592b07/m)
    check_as_text('T/T2154/T2154_013.xml', /0622a12.*\(出翻經圖單本.*0622a13/m)
    # check_as_text('X/X0281/X0281_002.xml', /0716b05.*二、示見性主空無遷義二.*0716b06/m)
    # check_as_text('X/X0288/X0288_001.xml', /0006a13.*<footnote>真鑑曰.*0006a14/m)
    # check_as_text('X/X0714/X0714_003.xml', /【經文資訊】卍新纂大日本續藏經 第 39-40 冊/m) # 卷跨冊    
    
    if @errors.empty?
      puts "\n未發現錯誤".green
      puts ElapsedTime.label(time_start)
    else
      puts "\n-----\n發現錯誤".red
      puts "-----"
      puts @errors.join("-----\n")
    end
  end

  private

  def check_as_text(fn, regex)    
    xml_path = Rails.root.join('data', 'xml4docx2', fn)
    unless File.exist?(xml_path)
      abort "檔案不存在: #{xml_path}"
    end

    print "\rcheck: #{xml_path}  "
    text = File.read(xml_path)
    if text !~ regex
      @errors << <<~MSG
        Error: check_as_text
        File: #{fn}
        應該要 match pattern：#{regex.source}
      MSG
    end
  end

  def do_file(xml_path)
    bn = File.basename(xml_path)
    print "\rcheck_xml4docx #{bn}  "

    @doc = File.open(xml_path) { |f| Nokogiri::XML(f) }
    unless @doc.errors.empty?
      @errors << "#{bn} XML not well-form: #{@doc.errors}\n"
      return
    end

    errors = @relaxng.validate(@doc)
    unless errors.empty?
      @errors << "#{bn} XML not valid ❌\n"
    end

    traverse(@doc.root)

    if @doc.at_xpath('//seg/seg')
      @errors << "#{bn} 有 seg 包 seg ❌\n"
    end
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
    if e.at_xpath('list | p').nil?
      abort "item 下面沒有 p, lb: #{$lb}, item: #{e.to_xml}" 
    end
    traverse(e)
  end
  
  def e_p(e)
    if e.key?('rend')
      rend = e['rend']
      if @doc.at_xpath("//styles/style[@name='#{rend}']").nil?
        warn "p rend: #{rend.inspect} 檔頭 style 未定義" 
      end
    end
    
    s = e.text.gsub(/\s/, '')
    if s.empty? and e.at_xpath('graphic').nil?
      abort "\np 的內容是空的, lb: #{$lb}, xml: #{e.to_xml}"
    end

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
      when 'p'    then e_p(c)
      when 'seg' then e_seg(c)
      else
        traverse(c)
      end
    end
  end

  def error(msg)
    location = caller_locations.first
    file = File.basename(location.path)
    abort "#{file}:#{location.lineno}, #{msg}"
  end

  def warn(msg)
    puts msg
    @log.puts msg
  end
end
