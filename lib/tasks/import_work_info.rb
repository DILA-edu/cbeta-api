require 'json'
require_relative 'cbeta_p5a_share'

class ImportWorkInfo
  def initialize
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
    @max_cjk_chars = 0
    @works_dynasty = Hash.new { |h, k| h[k] = [] }
    @works_no_dynasty = []

    init_regexp
    @work_xml_files = build_work_xml_files
  end
  
  def import
    @stat = {}
    @work_type = {}

    XmlFile.delete_all
    Place.delete_all
    Person.delete_all

    import_from_authority
    import_from_xml

    dynasty_combine_and_sort
    dynasty_write_count
    dynasty_write_works
    
    total = {}
    @stat['T'].each_key do |k|
      total[k] = @stat.values.sum { |x| x[k] }
    end

    puts "total_cjk_chars: %s" % number_with_delimiter(total[:cjk_chars_all])
    puts "total_en_words: %s" % number_with_delimiter(total[:en_words_all])
    puts "單部佛典最大字數 max_cjk_chars: %s" % number_with_delimiter(@max_cjk_chars)

    r = { total:, by_canon: @stat }
    fn = Rails.root.join('data', 'stat-all.json')
    puts "write #{fn}"
    File.write(fn, JSON.pretty_generate(r))
  end
  
  private

  def build_work_xml_files
    r = Hash.new { |h, k| h[k] = [] }
    Dir.glob("#{@xml_root}/**/*.xml") do |f|
      basename = File.basename(f, '.xml')
      id = CBETA.get_work_id_from_file_basename(basename)
      r[id] << basename
    end
    r
  end

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
        title << (y1<0 ? 'BCE' : 'CE')
        title << " ~ #{y2} "
        title << (y2<0 ? 'BCE' : 'CE')
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
    
    extent = doc.at_xpath("//extent").text
    r[:juan] = extent.delete_suffix('卷').to_i

    # 卷 milestone 可能跳號，要逐一列舉
    juan_list = []
    juans.each do |j|
      juan_list << j['n']
    end
    r[:juan_list_array] = juan_list
    
    r[:cjk_chars], r[:en_words] = count_chars(doc)
    r
  end
  
  def import_canon_from_xml(path)
    Dir.entries(path).sort.each do |f|
      next if f.start_with? '.'
      @vol = f
      $stderr.puts "import_work_info from xml #{@vol}"
      p = File.join(path, f)
      import_vol_from_xml(p)
    end
  end
    
  def import_from_xml
    @done = Set.new
    each_canon(@xml_root) do |c|
      @canon = c
      p = File.join(@xml_root, c)
      import_canon_from_xml(p)
    end
  end

  def init_stat_canon(canon)
    return if @stat.key?(canon)
    @stat[canon] = {
      works_all: 0,
      works_main: 0,
      juans_all: 0,
      juans_main: 0,
      cjk_chars_all: 0,
      cjk_chars_main: 0,
      en_words_all: 0,
      en_words_main: 0
    }
  end

  def import_from_authority
    @people = {}

    each_canon(@xml_root) do |c|
      @canon = c
      init_stat_canon(c)
      fn = File.join(@work_info_dir, "#{c}.json")
      puts "update from #{fn}"
      works_info = JSON.load_file(fn, symbolize_names: true)
      works_info.each do |k, v|
        @work_type[k.to_s] = v[:type]
        w = Work.find_or_create_by(n: k)
        if not v.key?(:alt)
          if v[:type]=="textbody"
            @stat[@canon][:works_main] += 1
            @stat[@canon][:juans_main] += v[:juans]
          end
          @stat[@canon][:works_all] += 1
          @stat[@canon][:juans_all] += v[:juans]
        end
        update_work_from_authority(w, v)
      end
    end

    insert_into_people
  end

  def insert_into_people
    inserts = []
    @people.each do |k, v|
      inserts << "('#{k}', '#{v}')"
    end

    puts "Insert #{inserts.size} records into people table:"
    sql = 'INSERT INTO people '
    sql << '("id2", "name")'
    sql << ' VALUES ' + inserts.join(", ")
    puts Benchmark.measure {
      ActiveRecord::Base.connection.execute(sql) 
    }
  end

  def update_contributors(w, v)
    return unless v.key?(:contributors)

    v[:contributors].each do |x|
      @people[x[:id]] = x[:name]
    end

    a = v[:contributors].map { |x| x[:name] }
    w.creators = a.join(',')

    a = v[:contributors].select { |x| x.key?(:id) }
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
    update_places(w, v[:places])

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
  
  def import_vol_from_xml(path)
    Dir.entries(path).sort.each do |f|
      next if f.start_with? '.'
      basename = File.basename(f, '.xml')
      @work = CBETA.get_work_id_from_file_basename(basename)
      p = File.join(path, f)
      import_work_from_xml(p)
    end
  end
  
  def import_work_from_xml(xml_path)
    return if @done.include? @work

    if @work_xml_files[@work].size > 1
      data = import_work_files
    else
      data = get_info_from_xml(xml_path)
      log_chars(data[:cjk_chars], data[:en_words])
      data[:cjk_chars] = data[:cjk_chars].size
      data[:en_words]  = data[:en_words].size

      update_xml_files(xml_path, @vol, data)
      
      update_work(data)
    end

    @done << @work

    @stat[@canon][:cjk_chars_all] += data[:cjk_chars]
    @stat[@canon][:en_words_all]  += data[:en_words]
    if @work_type[@work] == 'textbody'
      @stat[@canon][:cjk_chars_main] += data[:cjk_chars]
      @stat[@canon][:en_words_main]  += data[:en_words]
    end

    @max_cjk_chars = data[:cjk_chars] if data[:cjk_chars] > @max_cjk_chars
  end

  # 佛典跨冊時，讀取多個 XML 檔
  def import_work_files
    files = @work_xml_files[@work]

    data = nil
    @cjk_chars = ''
    @en_words = []
    files.each do |f|
      vol = f.sub(/^(.*?)n.*$/, '\1')
      xml_path = File.join(@xml_root, @canon, vol, f+'.xml')
      info = get_info_from_xml(xml_path)

      if data.nil?
        data = info
      else
        # 如果是 卷跨冊
        unless data[:juan_list_array].empty? and info[:juan_list_array].empty?
          if data[:juan_list_array].last == info[:juan_list_array].first
            info[:juan_list_array].shift
          end
        end
        data[:juan_list_array] += info[:juan_list_array]
      end

      update_xml_files(xml_path, vol, info)
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

  def update_places(w, places)
    return if places.nil?

    w.places.delete_all
    places.each do |h|
      place = Place.find_or_create_by(auth_id: h[:id]) do |p|
        p.name = h[:name]
        p.longitude = h[:long]
        p.latitude = h[:lat]
      end
      w.places << place
    end
  end

  def update_xml_files(xml_path, vol, info)
    basename = File.basename(xml_path, '.xml')
    XmlFile.find_or_create_by(work: @work, file: basename) do |w|
      w.vol = vol
      w.juan_start = info[:juan_start]
      w.juans = info[:juan]
    end
  end
  
  include CbetaP5aShare
end
