# frozen_string_literal: true

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

    fn = Rails.root.join('log', 'import_work_info.log')
    @log = File.open(fn, 'w')
    
    @work_uuid = read_uuid
    @max_cjk_chars = 0
    @works_dynasty = Hash.new { |h, k| h[k] = [] }
    @works_no_dynasty = []

    init_regexp
    @work_xml_files = build_work_xml_files
    
    @stat_folder = File.join(Rails.configuration.cb.dl, 'stat')
    FileUtils.makedirs(@stat_folder)
    FileUtils.makedirs(Rails.configuration.cb.sc)
  end
  
  def import
    @stat = {}
    @stat_vol = Hash.new { |h, k| h[k] = { chars: 0, cjk_chars: 0, en_words: 0 } }
    @stat_cat = Hash.new { |h, k| h[k] = { chars: 0, cjk_chars: 0, en_words: 0 } }
    @work_type = {}

    XmlFile.delete_all
    Place.delete_all
    Person.delete_all

    import_from_authority
    import_from_xml

    dynasty_combine_and_sort
    dynasty_write_count
    dynasty_write_works

    puts "Work   records: #{number_with_delimiter(Work.count)}"
    puts "Person records: #{number_with_delimiter(Person.count)}"
    puts "Place  records: #{number_with_delimiter(Place.count)}"
    
    total = {}
    @stat['T'].each_key do |k|
      total[k] = @stat.values.sum { |x| x[k] }
    end

    puts "total_cjk_chars: %s" % number_with_delimiter(total[:cjk_chars_all])
    puts "total_en_words: %s" % number_with_delimiter(total[:en_words_all])
    puts "單部佛典最大字數 max_cjk_chars: %s" % number_with_delimiter(@max_cjk_chars)

    r = { total:, by_canon: @stat }
    fn = File.join(@stat_folder, 'stat-all.json')
    puts "write #{fn}"
    File.write(fn, JSON.pretty_generate(r))

    write_word_count
    write_word_count_by_vol
    write_word_count_by_cat
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
        title = +"#{dynasties} #{y1} "
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
    fn = File.join(@stat_folder, 'dynasty-all.csv')
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
    fn = File.join(Rails.configuration.cb.sc, 'dynasty-works.json')
    puts "write #{fn}"
    File.write(fn, s)
  end
  
  def count_chars(doc)
    r = OpenStruct.new

    doc.at_xpath('//teiHeader').remove
    doc.xpath("//g").each { |x| x.content = '一' }
    doc.xpath("//unclear").each { |x| x.content = '⍰' }
    text_all = doc.text
    r.chars = text_all.size

    # 去除 xml document 中不列入計算的元素
    doc.xpath('//docNumber').each { |x| x.remove }
    doc.xpath("//figDesc").each { |x| x.remove }
    doc.xpath("//foreign[contains(@place, 'foot')]").each { |x| x.remove }
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
  
    text_cjk = doc.text.gsub(/\n/, '')
    en_words = []
    
    # 英數梵巴, 計算後去除
    text_cjk.gsub!(@regexp_en_word) do
      en_words << $& unless $& == '-'
      ''
    end
    r.en_words  = en_words.size
  
    # 去標點, 剩下的就是 CJK 字元
    text_cjk.gsub!(@regexp_not_cjk, '')
    r.cjk_chars = text_cjk.size

    log_chars(text_all, text_cjk, en_words)
    r
  end
  
  def get_info_from_xml(xml_path)
    @log.puts "#{__LINE__} get_info_from_xml: #{xml_path}"
    @work_bn = File.basename(xml_path, '.*')
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

    node = doc.at_xpath('//punctuation')
    if node and node.text == '新式標點'
      @new_punc_works[:all] << @work
      @new_punc_works[:cbeta] << @work if node['resp'] == 'CBETA'
      juan_list.each do |j|
        @new_punc_juans[:all] << "#{@work}-#{j.to_i}"
        @new_punc_juans[:cbeta] << "#{@work}-#{j.to_i}" if node['resp'] == 'CBETA'
      end
    end

    stat = count_chars(doc)
    r.merge!(stat.to_h)

    bn = File.basename(xml_path)
    vol = bn.sub(/^((?:#{CBETA::CANON})\d{2,3}).*$/, '\1')
    @log.puts "#{__LINE__} get_info_from_xml, #{bn}, vol: #{vol}"
    add_stat(stat, @stat_vol[vol])

    w = Work.find_by(n: @work)
    abort "#{__LINE__} #{@work} 在 Work 裡找不到" if w.nil?
    unless w.category.nil?
      w.category.split(',').each do |cat|
        add_stat(stat, @stat_cat[cat])
      end
    end

    r
  end

  def add_stat(src, dest)
    dest[:chars]     += src.chars
    dest[:cjk_chars] += src.cjk_chars
    dest[:en_words]  += src.en_words
  end
  
  def import_canon_from_xml(path)
    Dir.entries(path).sort.each do |f|
      next if f.start_with? '.'
      @vol = f
      @log.puts "#{__LINE__} vol: #{@vol}"
      $stderr.print "\rimport_work_info from xml #{@vol}   "
      p = File.join(path, f)
      import_vol_from_xml(p)
    end
  end
    
  def import_from_xml
    @done = Set.new
    each_canon(@xml_root) do |c|
      @canon = c
      @new_punc_works = { all: Set.new, cbeta: Set.new }
      @new_punc_juans = { all: Set.new, cbeta: Set.new }  
      p = File.join(@xml_root, c)
      import_canon_from_xml(p)
      @stat[@canon]["新標卷數"] = @new_punc_juans[:all].size
      @stat[@canon]["新標部數"] = @new_punc_works[:all].size
      @stat[@canon]["CBETA_新標卷數"] = @new_punc_juans[:cbeta].size
      @stat[@canon]["CBETA_新標部數"] = @new_punc_works[:cbeta].size
    end
    puts
  end

  def init_stat_canon(canon)
    return if @stat.key?(canon)
    @stat[canon] = {
      works_all: 0,
      works_main: 0,
      juans_all: 0,
      juans_main: 0,
      chars_all: 0,
      chars_main: 0,
      cjk_chars_all: 0,
      cjk_chars_main: 0,
      en_words_all: 0,
      en_words_main: 0
    }
  end

  def exist_in_cbeta?(work_id, work_info)
    alt = work_info[:alt]
    return true if alt.nil?
    
    # alt 裡有 選錄 二字，或有本身 work_id, 也列入統計
    return true if alt.include?('選錄')
    return true if alt.include?(work_id.to_s)
    false
  end

  def import_from_authority
    @people = []

    each_canon(@xml_root) do |c|
      @canon = c
      init_stat_canon(c)
      fn = File.join(@work_info_dir, "#{c}.json")
      print "\rupdate from authority #{File.basename(fn)}  "
      works_info = JSON.load_file(fn, symbolize_names: true)
      works_info.each do |k, v|
        @work_type[k.to_s] = v[:type]
        w = Work.find_or_create_by(n: k)
        if exist_in_cbeta?(k, v)
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
    puts

    Person.insert_all(@people, unique_by: :id2)
  end

  def update_contributors(w, v)
    return unless v.key?(:contributors)

    v[:contributors].each do |x|
      @people << { id2: x[:id], name: x[:name] } unless x[:id].blank?
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
    long_title = +"#{w.n} #{title}"
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
      update_xml_files(xml_path, @vol, data)
      update_work(data)
    end

    @done << @work

    @stat[@canon][:chars_all]     += data[:chars]
    @stat[@canon][:cjk_chars_all] += data[:cjk_chars]
    @stat[@canon][:en_words_all]  += data[:en_words]

    if @work_type[@work] == 'textbody'
      @stat[@canon][:chars_main]     += data[:chars]
      @stat[@canon][:cjk_chars_main] += data[:cjk_chars]
      @stat[@canon][:en_words_main]  += data[:en_words]
    end

    @max_cjk_chars = data[:cjk_chars] if data[:cjk_chars] > @max_cjk_chars
  rescue
    puts "#{__LINE__} xml_path: #{xml_path}, data: #{data.inspect}"
    raise
  end

  # 佛典跨冊時，讀取多個 XML 檔
  def import_work_files
    @log.puts "import_work_files, #{@work}"
    files = @work_xml_files[@work]

    data = nil
    chars = 0
    cjk_chars = 0
    en_words  = 0

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

      chars     += info[:chars]
      cjk_chars += info[:cjk_chars]
      en_words  += info[:en_words]
    end

    data[:chars]     = chars
    data[:cjk_chars] = cjk_chars
    data[:en_words]  = en_words

    update_work(data)
    data
  end

  def init_regexp
    # 構成 en_word 的字元
    s = +'\da-zA-Z'
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
    s += "\u0000-\u00FF" # C0 Controls and Basic Latin, C1 Controls and Latin-1 Supplement
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

  def log_chars(text_all, text_cjk, en_words)
    folder = Rails.root.join('log', 'import_work_info', @canon, @work)
    FileUtils.makedirs(folder)

    fn = File.join(folder, "#{@work_bn}-text-all.txt")
    File.write(fn, text_all)

    fn = File.join(folder, "#{@work_bn}-cjk-chars.txt")
    File.write(fn, text_cjk)

    unless en_words.empty?
      fn = File.join(folder, "#{@work_bn}-en-words.json")
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
      $stderr.puts "\n#{__LINE__} Work table 中無此編號: #{@work}".red
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

  def write_word_count
    fn = File.join(@stat_folder, "cbeta-word-count.csv")
    puts "write #{fn}"

    CSV.open(fn, "wb") do |csv|
      csv << %w[work chars cjk_chars en_words canon category alt]

      # 注意 部分收錄 的佛典，alt 屬性不是 nil, 例如 JA123
      Work.where.not(cjk_chars: nil).order(:n).each do |w|
        csv << [w.n, w.chars, w.cjk_chars, w.en_words, w.canon, w.category, w.alt]
      end
    end
  end

  def write_word_count_by_vol
    fn = File.join(@stat_folder, "cbeta-word-count-vol.csv")
    puts "write #{fn}"

    CSV.open(fn, "wb") do |csv|
      csv << %w[vol chars cjk_chars en_words]
      @stat_vol.keys.sort.each do |v|
        h = @stat_vol[v]
        csv << [v, h[:chars], h[:cjk_chars], h[:en_words]]
      end
    end
  end
  
  def write_word_count_by_cat
    fn = File.join(@stat_folder, "cbeta-word-count-cat.csv")
    puts "write #{fn}"

    CSV.open(fn, "wb") do |csv|
      csv << %w[category chars cjk_chars en_words]
      fn = Rails.root.join('data-static', 'categories.json')
      cats = JSON.load_file(fn)
      cats.each do |k, cat|
        h = @stat_cat[cat]
        csv << [cat, h[:chars], h[:cjk_chars], h[:en_words]]
      end
    end
  end

  include CbetaP5aShare
end
