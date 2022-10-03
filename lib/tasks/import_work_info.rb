require 'json'
require_relative 'cbeta_p5a_share'

class ImportWorkInfo
  def initialize
    folder = Rails.application.config.cbeta_data
    fn = File.join(folder, 'special-works', 'work-cross-vol.json')
    @work_cross_vol = File.open(fn) { |f| JSON.load(f) }

    @work_info_dir = Rails.configuration.x.work_info    
    @xml_root      = Rails.configuration.cbeta_xml
    
    @category_name2id = {}
    fn = Rails.root.join('data-static', 'categories.json')
    h = JSON.load_file(fn)
    h.each do |k, v|
      @category_name2id[v] = k
    end

    fn = Rails.root.join('log', 'import.log')
    @log = File.open(fn, 'w')
    
    @work_uuid = read_uuid
    @total_cjk_chars = 0
    @total_en_words = 0
    @max_cjk_chars = 0
    @works_dynasty = Hash.new { |h, k| h[k] = [] }
    @works_no_dynasty = []

    init_regexp
  end
  
  def import
    import_from_authority
    import_from_xml

    dynasty_combine_and_sort
    dynasty_write_count
    dynasty_write_works    
    
    puts "total_cjk_chars: %s" % number_with_delimiter(@total_cjk_chars)
    puts "total_en_words: %s" % number_with_delimiter(@total_en_words)
    puts "單部佛典最大字數 max_cjk_chars: %s" % number_with_delimiter(@max_cjk_chars)
  end
  
  private

  def dynasty_combine_and_sort
    @dynasty_works = []
    @dynasty_works_count = []

    # 朝代順序依據 dynasty-year.csv
    fn = Rails.root.join('data-static', 'dynasty-order.csv')
    CSV.foreach(fn, headers: true) do |row|
      dynasties = row['dynasty']
      y1 = row['time_from'].to_i
      y2 = row['time_to'].to_i
      
      works = []
      dynasties.split('/').each do |dynasty|
        next unless @works_dynasty.key? dynasty
        next if @works_dynasty[dynasty].empty?
        works += @works_dynasty[dynasty]
        @works_dynasty.delete dynasty
      end
      
      unless works.empty?
        @dynasty_works_count << [dynasties, y1, y2, works.size]
        
        dynasty_h = { key: dynasties }
        title = "#{dynasties} #{y1} "
        title << y1<0 ? 'BCE' : 'CE'
        title << " ~ #{y2} "
        title << y2<0 ? 'BCE' : 'CE'
        dynasty_h[:title] = title
        dynasty_h[:children] = works
        @dynasty_works << dynasty_h
      end
    end

    @dynasty_works << {
      key: 'unknown',
      title: '朝代未知',
      children: @works_no_dynasty
    }
  end

  def dynasty_write_count
    fn = Rails.root.join('data', 'dynasty-all.csv')
    puts "write #{fn}"
    CSV.open(fn, "wb") do |csv|
       csv << %w(朝代 起始年 結束年 典籍數)
       @dynasty_works_count.each do |a|
         csv << a
       end
    end
  end

  def dynasty_write_works
    r = [
      {
        title: '選擇全部',
        children: @dynasty_works
      }
    ]
    s = JSON.pretty_generate(r)
    fn = Rails.root.join('data', 'dynasty-works.json')
    puts "write #{fn}"
    File.write(fn, s)
  end
  
  
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
    
  def import_from_xml
    @done = Set.new
    each_canon(@xml_root) do |c|
      @canon = c
      p = File.join(@xml_root, c)
      import_canon(p)
    end
  end

  def import_from_authority
    @people_inserts = []

    each_canon(@xml_root) do |c|
      @canon = c
      fn = File.join(@work_info_dir, "#{c}.json")
      puts "update from #{fn}"
      works_info = JSON.load_file(fn, symbolize_names: true)
      works_info.each do |k, v|
        w = Work.find_or_create_by(n: k)
        update_work_from_authority(w, v)
      end
    end

    insert_into_people
  end

  def insert_into_people
    puts "Insert #{@people_inserts.size} records into people table:"
    sql = 'INSERT INTO people '
    sql += '("id2", "name")'
    sql += ' VALUES ' + @people_inserts.join(", ")
    puts Benchmark.measure {
      ActiveRecord::Base.connection.execute(sql) 
    }
  end

  def update_contributors(w, v)
    return unless v.key?(:contributors)

    people = v[:contributors]
    people.each do |x|
      @people_inserts << "('#{x[:id]}', '#{x[:name]}')"
    end

    a = people.map { |x| x[:name] }
    w.creators = a.join(',')

    a = people.select { |x| x.key?(:id) }
    a.map! { |x| "#{x[:name]}(#{x[:id]})" }
    w.creators_with_id = a.join(';')
  end

  def update_dynasty(w, v, title)
    work_h = {
      key: w.n,
      title: title
    }

    if v.key?(:dynasty)
      d = v[:dynasty]
      w.time_dynasty = d      
      @works_dynasty[d] << work_h
    else
      w.time_dynasty = 'unknown'
      @works_no_dynasty << work_h
    end
  end

  def update_work_from_authority(w, v)
    w.canon     = @canon
    w.vol       = v[:vol]
    w.title     = v[:title]
    w.juan      = v[:juans]
    w.byline    = v[:byline]
    w.work_type = v[:type] || 'textbody' # 預設：正文

    title = v[:title]
    long_title = "#{w.n} #{title}"
    unless %w(N Y ZS ZW).include? @canon
      long_title << " (#{v[:juans]}卷)"
    end
    long_title << "【#{v[:byline]}】" if v.key?(:byline)

    update_contributors(w, v)
    update_dynasty(w, v, long_title)
    update_category(w, v)

    w.time_from = v[:time_from] if v.key?(:time_from)
    w.time_to   = v[:time_to]   if v.key?(:time_to)

    if v.key?(:alt)
      # 例 B0130 因為 CBETA 也有選錄部份為 B23n0130, 所以不把 B0130 當做 alt
      unless v[:alt].include? '選錄'        
        w.alt = v[:alt]
      end
    end

    w.save
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
      
      update_work(data)
    end

    @done << @work
    @total_cjk_chars += data[:cjk_chars]
    @total_en_words += data[:en_words]
    @max_cjk_chars = data[:cjk_chars] if data[:cjk_chars] > @max_cjk_chars
  end

  # 佛典跨冊時，讀取多個 XML 檔
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

  def update_category(w, v)
    w.orig_category = v[:orig_category] if v.key?(:orig_category)

    return unless v.key?(:category)

    names = v[:category]
    w.category = names

    # 一部佛典可能屬於多個部類，例如 T2732
    a = names.split(',').map do |name|
      if @category_name2id.key?(name)
        @category_name2id[name]
      else
        abort "#{__LINE__} category name 不存在： #{name}"
      end
    end
    w.category_ids = a.join(',')
  end

  def update_work(data)
    w = Work.find_by n: @work
    if w.nil?
      $stderr.puts "#{__LINE__} Work table 中無此編號: #{@work}"
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
