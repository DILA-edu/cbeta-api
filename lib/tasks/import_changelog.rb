class ImportChangelog
  IN = '/Users/ray/Downloads/2025R2-text.htm'

  LINEHEAD = /
    [A-Z]{1,2}\d{2,3} # 冊號
    n[a-zA-Z\d]\d{3}[_a-zA-Z] # 經號
    p[a-z\d]\d{3} # 頁
    [a-z] # 欄
    \d\d # 行
  /x

  def initialize
    fn = Rails.root.join('log', 'import_changelog.log')
    @log = File.open(fn, 'w')
  end

  def import(ver)
    abort "ver 不能是空的" if ver.blank?
    @inserts = []
    
    fn = File.join(Rails.configuration.cb.changelog, "#{ver}-text.htm")
    abort "檔案不存在: #{fn}" unless File.exist?(fn)

    body = File.read(fn).sub(/\A.*<body>(.*)<\/body>.*\z/m, '\1')

    body.split("\n") do |line|
      next if line.empty?

      line.sub!(/^(<span class="(?:ins|del)">)(#{LINEHEAD}║)/, '\2\1')

      if line.match(/^(#{LINEHEAD})║(.*)<br>/)
        insert_line($1, $2, ver)
      elsif not line =~ /^<h\d>.*<\/h\d>$/
        abort "[#{__LINE__}] 例外: #{line.inspect}"
      end
    end

    puts "新增筆數: #{number_with_delimiter(@inserts.size)}"
    Change.insert_all(@inserts)
    puts "Change 總筆數: #{number_with_delimiter(Change.count)}"
  end

  private
  
  def insert_line(lb, html, ver)
    html.gsub!(/(?:<span class="del">[^<]*<\/span>){2,}/) { merge_del(it) }
    line = Line.find_by(linehead: lb)
    abort "在 lines 裡找不到 linehead: #{lb}" if line.nil?
    @inserts << { lb:, html:, ver:, work: line.work, juan: line.juan }
    @log.puts @inserts.last
  end

  def merge_del(match)
    r = match.gsub(/<[^>]+>/, '')
    %(<span class="del">#{r}</span>)
  end
end