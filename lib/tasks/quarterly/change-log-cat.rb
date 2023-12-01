class ChangeLogCategory

  PUNCS = " " + CbetaString::PUNCS

  def initialize(config)
    @config = config
    @base = config[:change_log]
  end

  def run
    @quarter = @config[:q2]
    @log = File.open('cat.log', 'w')
    @f_text = ''
    @f_punc = ''
  
    @body = false
    i = 0
    fn = File.join(@base, "#{@quarter}.htm")
    puts "read #{fn}"
    File.open(fn).each do |line|
      line.chomp!
      next if line.empty?
      break if handle_line(line) == 'break'
      i += 1
      puts i if (i % 1000) == 0
    end
  
    # 去除像這種的:
    # <h2>A098n1276《大唐開元釋教廣品歷章》卷9</h2>
    # <del>新編入錄</del><br>
    # <ins>A098n1276_p0115b01║新編入錄</ins><br>
    @f_text.gsub!(/<h2>[^<]*<\/h2>\n<del>([^<]*)<\/del><br>\n<ins>[^║]*║\1<\/ins>(<br>)?\n/, '')
  
    fn = File.join(@base, "#{@quarter}-text.htm")
    puts "write #{fn}"
    File.write(fn, @f_text)
  
    fn = File.join(@base, "#{@quarter}-punc.htm")
    puts "write #{fn}"
    File.write(fn, @f_punc)
  end

  private

  def handle_line(line)
    @log.puts line
    if @body
      if line.start_with? '<h2'
        @head_text = line
        @head_punc = line
      elsif line=='</body></html>'
        @f_text << line + "\n"
        @f_punc << line + "\n"
        return 'break'
      else
        #$dirty = handle_line_text(line)
        handle_line_text(line)
        #handle_line_punc(line) unless $dirty
        handle_line_punc(line)
      end
    else
      if line.start_with? '<h1'
        @f_text << "<h1>CBETA #{@quarter} 文字變更記錄</h1>\n"
        @f_punc << "<h1>CBETA #{@quarter} 標點變更記錄</h1>\n"
      elsif line.start_with? '<h2'
        @body = true
      else
        @f_text << line + "\n"
        @f_punc << line + "\n"
      end
    end
  end

  def handle_line_text(line)
    return false if line.match(/^<(del|ins)>[^<]+║<\/\1>(<br>)?$/)  # 只有行號，沒有文字

    s = line.gsub(/<del>(.*?)<\/del>/) do
      remove_puncs($1, 'del')
    end
    
    s.gsub!(/<ins>(.*?)<\/ins>/) do
      remove_puncs($1, 'ins')
    end
    
    return false unless s.include?('<del>') or s.include?('<ins>')
    
    unless @head_text.nil?
      @f_text << @head_text + "\n"
      @head_text = nil
    end
    
    @f_text << s + "\n"
    true
  end

  def handle_line_punc(line)
    return if line.match(/^<(del|ins)>[^<]+║<\/\1>(<br>)?$/) # 只有行號，沒有文字
    
    # 整行新增或刪除
    return if line.match(/^<(del|ins)>[^<]+║.*<\/\1><br>$/)

    s = line.gsub(/<del>(.*?)<\/del>/) do
      remove_texts($1, 'del')
    end
    
    s.gsub!(/<ins>(.*?)<\/ins>/) do
      remove_texts($1, 'ins')
    end
    
    return unless s.include?('<del>') or s.include?('<ins>')

    unless @head_punc.nil?
      @f_punc << @head_punc + "\n"
      @head_punc = nil
    end
    
    @f_punc << s + "\n"
  end

  def remove_puncs(s, tag)
    r = ''
    s2a(s).each do |c|
      if PUNCS.include? c
        r << c if tag == 'ins'
      else
        r << "<#{tag}>#{c}</#{tag}>"
      end
    end
    r.gsub!(/<\/#{tag}><#{tag}>/, '')
    r
  end

  def remove_texts(s, tag)
    r = ''
    s2a(s).each do |c|
      if PUNCS.include? c
        r << "<#{tag}>#{c}</#{tag}>"
      else
        r << c if tag == 'ins'
      end
    end
    r.gsub(/<\/#{tag}><#{tag}>/, '')
  end

  # 字串轉為矩陣
  # 組字式 當做一個字
  def s2a(s)
    s.scan(/\[[^\]]+\]|./)
  end

end
