require 'json'
require_relative 'cbeta_p5a_share'

class ImportWorkInfo
  def initialize
    @data_folder = Rails.application.config.cbeta_data
    
    fn = File.join(@data_folder, 'special-works', 'work-cross-vol.json')
    @work_cross_vol = File.open(fn) { |f| JSON.load(f) }
    
    @xml_root = Rails.application.config.cbeta_xml
    
    fn = Rails.root.join('log', 'import.log')
    @log = File.open(fn, 'w')
    
    @work_uuid = read_uuid
    @total_cjk_chars = 0
    @total_en_words = 0
    @max_cjk_chars = 0

    init_regexp
  end
  
  def import
    import_from_xml
    import_from_alt
    import_title_from_metadata
    puts "total_cjk_chars: %s" % number_with_delimiter(@total_cjk_chars)
    puts "total_en_words: %s" % number_with_delimiter(@total_en_words)
    puts "max_cjk_chars: %s" % number_with_delimiter(@max_cjk_chars)
  end
  
  private

  def count_chars(doc)
    # 去除 xml document 中不列入計算的元素
    doc.at_xpath('//teiHeader').remove
    doc.xpath('//docNumber').each { |x| x.remove }
    doc.xpath("//figDesc").each { |x| x.remove }
    doc.xpath("//foreign[contains(@place, 'foot')]").each { |x| x.remove }
    doc.xpath("//g").each { |x| x.content = '一' }
    doc.xpath("//mulu").each { |x| x.remove }
    doc.xpath("//note[@type='add']").each { |x| x.remove }
    doc.xpath("//note[@type='cf1']").each { |x| x.remove }
    doc.xpath("//note[@type='cf2']").each { |x| x.remove }
    doc.xpath("//note[@type='cf3']").each { |x| x.remove }
    doc.xpath("//note[@type='mod']").each { |x| x.remove }
    doc.xpath("//note[@type='orig']").each { |x| x.remove }
    doc.xpath("//note[contains(@place, 'foot')]").each { |x| x.remove }
    doc.xpath("//orig").each { |x| x.remove }
    doc.xpath("//rdg").each { |x| x.remove }
    doc.xpath("//sic").each { |x| x.remove }
    doc.xpath("//t[contains(@place, 'foot')]").each { |x| x.remove }
    doc.xpath("//unclear").each { |x| x.content = '⍰' }
  
    text = doc.text.gsub(/\n/, '')
    en_words = []
    
    # 英數梵巴, 計算後去除
    text.gsub!(@regexp_en_word) do
      en_words << $& unless $& == '-'
      ''
    end
  
    # 去標點, 剩下的就是 CJK 字元
    text.gsub!(@regexp_not_cjk, '')
    
    return text, en_words
  end
  
  def get_info_from_xml(xml_path)
    r = {}
    doc = File.open(xml_path) { |f| Nokogiri::XML(f) }
    doc.remove_namespaces!
    
    s = doc.at_xpath('//titleStmt/title').text
    s = s.split[-1]
    s.sub!(/^(.*)\(.*?\)$/, '\1')
    r[:title] = s
    
    s = doc.at_xpath('//fileDesc/extent').text
    s.sub!(/^(\d+)卷$/, '\1')
    r[:juan] = s.to_i
    
    juans = doc.xpath("//milestone[@unit='juan']")
    r[:juan_start] = juans.first['n'].to_i
    
    # 卷 milestone 可能跳號，要逐一列舉
    juan_list = []
    juans.each do |j|
      juan_list << j['n']
    end
    r[:juan_list_array] = juan_list
    
    r[:cjk_chars], r[:en_words] = count_chars(doc)
    r
  end
  
  def import_canon(path)
    Dir.entries(path).sort.each do |f|
      next if f.start_with? '.'
      @vol = f
      $stderr.puts "import_work_info #{@vol}"
      p = File.join(path, f)
      import_vol(p)
    end
  end
  
  def import_from_alt
    folder = File.join(Rails.application.config.cbeta_data, 'alternates')
    Dir["#{folder}/*.json"].each do |fn|
      $stderr.puts "import_work_info from #{fn}"
      basename = File.basename(fn, '.*')
      @canon = fn.sub(/^.*alt\-([a-z]+).json$/, '\1').upcase
      alts = File.open(fn) { |f| JSON.load(f) }
      alts.each_pair do |k,v|
        next if v['alt'].include? '選錄'
        @work = k
        update_work title: v['title'], alt: v['alt']
      end
    end
  end  
  
  def import_from_xml
    @done = Set.new
    each_canon(@xml_root) do |c|
      @canon = c
      p = File.join(@xml_root, c)
      import_canon(p)
    end
  end

  def import_title_from_metadata
    @data_folder = Rails.application.config.cbeta_data
    fn = File.join(@data_folder, 'titles', 'all-title-byline.csv')
    CSV.foreach(fn, headers: true) do |row|
      w = Work.find_by n: row['典籍編號']
      if w.nil?
        $stderr.puts "Work table 中無此編號: #{row['典籍編號']}"
      else
        w.update(title: row['典籍名稱'])
      end
    end
  end
  
  def import_vol(path)
    Dir.entries(path).sort.each do |f|
      next if f.start_with? '.'
      basename = File.basename(f, '.xml')
      @work = CBETA.get_work_id_from_file_basename(basename)
      p = File.join(path, f)
      import_work(p)
    end
  end
  
  def import_work(xml_path)
    return if @done.include? @work

    if @work_cross_vol.key? @work
      data = import_work_files
    else
      data = get_info_from_xml(xml_path)
      log_chars(data[:cjk_chars], data[:en_words])
      data[:cjk_chars] = data[:cjk_chars].size
      data[:en_words]  = data[:en_words].size

      update_xml_files(xml_path, data[:juan], data[:juan_start])
      
      data[:alt] = nil
      update_work(data)
    end

    @done << @work
    @total_cjk_chars += data[:cjk_chars]
    @total_en_words += data[:en_words]
    @max_cjk_chars = data[:cjk_chars] if data[:cjk_chars] > @max_cjk_chars
  end

  # 典籍跨冊時，讀取多個 XML 檔
  def import_work_files
    files = @work_cross_vol[@work]
    unless files.kind_of?(Array)
      files = files['files']
    end

    data = nil
    @cjk_chars = ''
    @en_words = []
    files.each do |f|
      vol = f.sub(/^(.*?)n.*$/, '\1')
      xml_path = File.join(@xml_root, @canon, vol, f+'.xml')
      info = get_info_from_xml(xml_path)
      if data.nil?
        data = info
        update_xml_files(xml_path, data[:juan], data[:juan_start])
      else
        data[:juan] += info[:juan]

        # 如果是 卷跨冊
        unless data[:juan_list_array].empty? and info[:juan_list_array].empty?
          if data[:juan_list_array].last == info[:juan_list_array].first
            info[:juan_list_array].shift
            data[:juan] -= 1
          end
        end
        
        data[:juan_list_array] += info[:juan_list_array]
      end
      @cjk_chars += info[:cjk_chars]
      @en_words  += info[:en_words]
    end

    data[:cjk_chars] = @cjk_chars.size
    data[:en_words]  = @en_words.size
    log_chars(@cjk_chars, @en_words)

    data[:alt] = nil
    update_work(data)

    data
  end

  def init_regexp
    # 構成 en_word 的字元
    s = '\da-zA-Z'
    s << "'"  # don't 算一個 word
    s << '\-' # Saddharma-puṇḍarīka 算一個 word
    s << "\u00C0-\u00D6" # C1 Controls and Latin-1 Supplement => Letters
    s << "\u00D8-\u00F6" # C1 Controls and Latin-1 Supplement => Letters
    s << "\u00F8-\u00FF" # C1 Controls and Latin-1 Supplement => Letters
    s << "\u0100-\u017F" # Latin Extended-A
    s << "\u0180-\u024F" # Latin Extended-B
    s << "\u02BC"        # MODIFIER LETTER APOSTROPHE
    s << "\u0300-\u036F"
    s << "\u0370-\u04FF" # Greek and Coptic, Cyrillic
    s << "\u1E00-\u1EFF" # Latin Extended Additional
    s << "\u2150-\u218F" # Number Forms
    s << "\u2460-\u24FF" # Enclosed Alphanumerics: ①②③④⑤⑥⑦⑧⑨⑩
    s << "\u2C60-\u2C7F" # Latin Extended-C
    s << "\uA720-\uA7FF" # Latin Extended-D
    s << "\uAB30-\uAB6F" # Latin Extended-E
    s << "\uFF10-\uFF19" # ０１２３４５６７８９
    s << "\uFF21-\uFF3A" # Ａ..Ｚ
    s << "\uFF41-\uFF5A" # ａｂｃｄｅｉｕ
    @regexp_en_word = Regexp.new("[#{s}]+")

    # 不計入 cjk_chars 的字元
    s = "\u0000-\u00FF" # C0 Controls and Basic Latin, C1 Controls and Latin-1 Supplement
    s << "\u02B0-\u036F" # ʼˇˋ ̐
    s << "\u2000-\u206F" # – — ’ “ ” … ‧ ※ ⁉
    s << "\u2150-\u218F" # ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ
    s << "\u2190-\u22FF" # ←↑→↓↖↗↘↙∕√∞∟∠∴∵≡⊕⊙⊥
    s << "\u2460-\u26FF" # ①..⑩─│┌┐└┘├┤┬┴┼═║╭╮╯╰╱╲╳▔■□▲△▽◇○◎●◐◑☆
    s << "\u2C60-\u2C7F" # Latin Extended-C
    s << "\u3000-\u3002" # 全形空格、。
    s << "〄"
    s << "\u3008-\u3011" # 〈〉《》「」『』【】
    s << "\u3014-\u301F" # 〔〕
    s << "〰〷"
    s << "\u303D-\u303F" # 〽〾〿
    s << "\uFE30-\uFE6F" # ︵︶﹁﹂﹄﹏﹐﹑﹒﹔﹕﹖﹗﹘﹙﹚﹛﹜﹝﹞﹟﹠﹡﹢﹣﹤﹥﹦﹨﹩﹪﹫
    s << "\uFF01-\uFF64" # ！＆＇（）＊＋，－．／０１..９：；＜＝＞？＠Ａ..Ｚ［＼］＾＿｀ａ..ｚ｜｝～
    @regexp_not_cjk = Regexp.new("[#{s}]+")
  end

  def log_chars(cjk_chars, en_words)
    folder = Rails.root.join('log', 'import_work_info', @canon, @work)
    FileUtils.rm_rf(folder) if Dir.exist?(folder)
    FileUtils.makedirs(folder)

    fn = File.join(folder, "#{@work}-cjk-chars.txt")
    File.write(fn, cjk_chars)

    unless en_words.empty?
      fn = File.join(folder, "#{@work}-en-words.json")
      s = JSON.generate(en_words)
      File.write(fn, s)
    end
  end
  
  def read_uuid
    fn = Rails.root.join('data-static', 'uuid', 'works.json')
    s = File.read(fn)
    JSON.parse(s)
  end
  
  def update_work(data)
    w = Work.find_by n: @work
    if w.nil?
      $stderr.puts "Work table 中無此編號: #{@work}"
    else
      if data.key? :juan_list_array
        data[:juan_list] = data[:juan_list_array].join(',')
        data.delete(:juan_list_array)
      end
      data[:canon] = @canon
      data[:uuid] = @work_uuid[w.n]
      w.update(data)
    end
  end
  
  def update_xml_files(xml_path, juans, juan_start)
    XmlFile.find_or_create_by(vol: @vol, work: @work) do |w|
      w.file = File.basename(xml_path, '.xml')
      w.juans =  juans
      w.juan_start = juan_start
    end
  end
  
  include CbetaP5aShare
end