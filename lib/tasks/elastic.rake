# Elasticsearch index 的建立、匯入與 alias 切換。
#
# <type> 是 text / notes / titles / chunks 其中之一 (省略時為 text)。
# 見 doc/elasticsearch-migration.md
namespace :elastic do
  INDEX_CLASSES = {
    'text' => 'CbetaSearch::TextIndex',
    'notes' => 'CbetaSearch::NotesIndex',
    'titles' => 'CbetaSearch::TitlesIndex',
    'chunks' => 'CbetaSearch::ChunksIndex'
  }.freeze
  desc '啟動本機 Elasticsearch (Docker Compose)'
  task :start do
    ensure_docker_daemon!
    run_elastic_compose!('up', '-d')
  end

  desc '停止本機 Elasticsearch'
  task :stop do
    run_elastic_compose!('down')
  end

  desc '顯示本機 Elasticsearch 服務狀態'
  task :status do
    run_elastic_compose!('ps')
  end

  desc '顯示 Elasticsearch 連線、index 與 alias 資訊'
  task info: :environment do
    conf = Rails.configuration.x.elasticsearch
    puts "url:         #{conf.url}"
    puts "index_name:  #{conf.index_name}  (只是 text 的預設值)"
    puts "\naliases / 匯入來源:"
    INDEX_CLASSES.each_key do |type|
      klass = index_class(type)
      xml = begin
        klass.xml_path
      rescue KeyError
        '(config.x.elasticsearch.xml 沒有這一項)'
      end
      puts format('  %-7s %-26s %s', type, klass.index_alias, xml)
    end

    client = CbetaSearch::ElasticClient.build
    puts "\nindices:"
    print_indices(client)
    puts "\nalias 指向:"
    INDEX_CLASSES.each_key do |type|
      alias_name = index_class(type).index_alias
      # alias 還沒建立時 ES 回 404 (ignore_unavailable 只對 index 有效)。
      # 這正是遷移途中的正常狀態，診斷指令不該因此中斷。
      targets = begin
        client.indices.get_alias(name: alias_name)
      rescue Elastic::Transport::Transport::Errors::NotFound
        {}
      end
      if targets.empty?
        puts "  #{alias_name} 尚未指向任何 index"
      else
        targets.each_key { |index| puts "  #{alias_name} -> #{index}" }
      end
    end
  rescue StandardError => e
    abort "讀取 Elasticsearch 資訊失敗 (#{conf.url})：#{e.class}: #{e.message}"
  end

  desc '建立 index，例：rake elastic:create_index[text,cbeta_text_2026r3_001]'
  task :create_index, [:type, :index_name] => :environment do |_task, args|
    type, index_name = resolve_target(args)
    refuse_if_live!(type, index_name)
    index_class(type).new.create!(index_name)
    puts "已建立 index：#{index_name}"
  end

  desc '匯入 xmlpipe2 XML，例：rake elastic:import[notes,cbeta_notes_2026r3_001]'
  task :import, [:type, :index_name, :xml_path] => :environment do |_task, args|
    type, index_name = resolve_target(args)
    import_xml(type, index_name, args[:xml_path].presence)
  end

  desc '（相容舊名）等同 elastic:import[text,...]'
  task :import_text, [:index_name, :xml_path] => :environment do |_task, args|
    index_name = resolve_index_name('text', args[:index_name])
    import_xml('text', index_name, args[:xml_path].presence)
  end

  desc '把 alias 切到指定 index，例：rake elastic:promote[text,cbeta_text_2026r3_001]'
  task :promote, [:type, :index_name] => :environment do |_task, args|
    type, index_name = resolve_target(args)
    klass = index_class(type)
    klass.new.promote!(index_name)
    puts "已將 alias #{klass.index_alias} 切到 #{index_name}"
  end

  desc '建立 index、匯入、切換 alias，例：rake elastic:rebuild[notes,cbeta_notes_2026r3_001]'
  task :rebuild, [:type, :index_name, :xml_path] => :environment do |_task, args|
    type, index_name = resolve_target(args)
    rebuild_one(type, index_name, args[:xml_path].presence)
  end

  desc '一次重建四個 index，例：rake elastic:rebuild_all[2026r3]'
  task :rebuild_all, [:release, :serial] => :environment do |_task, args|
    release = args[:release].presence or abort "請指定季號，例：rake 'elastic:rebuild_all[2026r3]'"
    serial = args[:serial].presence || '001'

    INDEX_CLASSES.each_key do |type|
      rebuild_one(type, index_class(type).versioned_index_name(release, serial), nil)
      puts
    end
  end

  desc '檢查 analyzer 輸出，例：rake elastic:analyze[阿含]'
  task :analyze, [:text] => :environment do |_task, args|
    text = args[:text].presence || '阿含'
    # 四個 index 的 analyzer 定義相同，用哪一個問都一樣
    tokens = CbetaSearch::TextIndex.new.analyze(text).fetch('tokens').map { it.fetch('token') }
    puts "#{tokens.size} tokens: #{tokens.join('|')}"
  end

  desc '抓取搜尋結果 golden values，例：rake elastic:fetch_golden[https://cbdata.dila.edu.tw/stable]'
  task :fetch_golden, [:base_url] => :environment do |_task, args|
    base = args[:base_url].presence || 'https://cbdata.dila.edu.tw/stable'
    path = golden_path
    result = {}

    GOLDEN_CASES.each do |name, endpoint, params|
      result[name] = fetch_golden_case(base, endpoint, params)
      puts format('  %-22s %s', name, result[name][:num_found] || result[name][:hits] ||
                                      result[name][:facet_size] || result[name][:error])
    end
    result[:_meta] = { source: base, fetched_at: Time.current.iso8601 }

    File.write(path, JSON.pretty_generate(result))
    puts "已寫入 #{path} (來源: #{base})"
  end

  desc '比對本機搜尋結果與 golden values，例：rake elastic:verify_golden[http://localhost:3000]'
  task :verify_golden, [:base_url] => :environment do |_task, args|
    base = args[:base_url].presence || 'http://localhost:3000'
    path = golden_path
    abort "找不到 golden values：#{path}，請先執行 rake elastic:fetch_golden" unless File.exist?(path)

    golden = JSON.parse(File.read(path), symbolize_names: true)
    if (meta = golden[:_meta])
      puts "golden 來源: #{meta[:source]}（抓取於 #{meta[:fetched_at]}）"
      puts
    end
    same = 0
    diff = []

    GOLDEN_CASES.each do |name, endpoint, params|
      expected = golden[name.to_sym]
      next puts format('  %-22s 略過 (golden 沒有這一項)', name) if expected.nil?

      actual = fetch_golden_case(base, endpoint, params)
      report = compare_golden(expected, actual)
      if report[:same]
        same += 1
      else
        diff << name
      end
      puts format('  %-4s %-22s %s', report[:same] ? 'OK' : 'DIFF', name, report[:message])
    end

    puts
    puts "一致 #{same} / #{GOLDEN_CASES.size}"
    puts "不一致: #{diff.join(', ')}" if diff.any?
    puts '註: 若本機 data/search-xml/*.xml 與 golden 來源不同季，差異會落在資料版本上。'
  end

  # 驗收用的查詢清單。涵蓋對外承諾的 7 種查詢語法、各個 filter、排序與 facet。
  GOLDEN_CASES = [
    ['basic_phrase',       'search',              { q: '法鼓' }],
    ['basic_ahan',         'search',              { q: '阿含' }],
    # AND / OR / NOT 走 all_in_one: 舊版 search 與 search/extended 會把已含雙引號的 q
    # 再包一層引號, 語法因此失效 (實測 q="法鼓" 得到「法」AND「鼓」的結果),
    # 所以基準取自語法正確的 all_in_one。詳見 doc/elasticsearch-migration.md
    ['ext_and',            'search/all_in_one',   { q: '"法鼓" "迦葉佛"', fields: 'work,juan,term_hits' }],
    ['ext_or',             'search/all_in_one',   { q: '"波羅蜜" | "波羅密"', fields: 'work,juan,term_hits' }],
    ['ext_not',            'search/all_in_one',   { q: '"迦葉" !"迦葉佛"', fields: 'work,juan,term_hits' }],
    ['aio_near2',          'search/all_in_one',   { q: '"法鼓" NEAR/7 "迦葉"', fields: 'work,juan,term_hits' }],
    ['aio_near3',          'search/all_in_one',   { q: '"老子" NEAR/7 "道" NEAR/3 "經"', fields: 'work,juan,term_hits' }],
    ['aio_exclude_suffix', 'search/all_in_one',   { q: '"舍利" -"舍利弗"', fields: 'work,juan,term_hits' }],
    ['aio_exclude_prefix', 'search/all_in_one',   { q: '"直心" -"正直心"', fields: 'work,juan,term_hits' }],
    ['latin_pali',         'search',              { q: 'Pāli Text Society' }],
    ['latin_ananda',       'search',              { q: 'Ānanda' }],
    ['latin_ananda_plain', 'search',              { q: 'Ananda' }],
    ['latin_apostrophe',   'search',              { q: "samantato \\'nantanāvāptiśāsani" }],
    ['gaiji_zzs',          'search',              { q: '[幻-ㄠ+糸]' }],
    ['cjk_compat',         'search',              { q: "\u{2F8BB}" }],
    ['kangxi_radical',     'search',              { q: '⾔' }],
    ['filter_canon',       'search',              { q: '法鼓', canon: 'T' }],
    ['filter_canon_multi', 'search',              { q: '法鼓', canon: 'T,X' }],
    ['filter_category',    'search',              { q: '法鼓', category: '阿含部類' }],
    ['filter_creator',     'search',              { q: '法鼓', creator: 'A001583' }],
    ['filter_dynasty',     'search',              { q: '法鼓', dynasty: '唐' }],
    ['filter_time_range',  'search',              { q: '法鼓', time: '600..700' }],
    ['filter_work_type',   'search',              { q: '法鼓', work_type: 'textbody' }],
    ['filter_note0',       'search',              { q: '法鼓', note: '0' }],
    ['order_term_hits',    'search',              { q: '法鼓', order: 'term_hits' }],
    ['order_time_from',    'search',              { q: '法鼓', order: 'time_from' }],
    ['paginate',           'search',              { q: '法鼓', start: '100', rows: '5' }],
    ['facet_canon',        'search/facet/canon',   { q: '法鼓' }],
    ['facet_dynasty',      'search/facet/dynasty', { q: '法鼓' }],
    ['facet_category',     'search/facet/category', { q: '法鼓' }],
    ['sc',                 'search/sc',           { q: '观世音' }],

    # --- 第二期: notes index ---
    ['notes_phrase',       'search/notes',        { q: '"法鼓"' }],
    ['notes_and',          'search/notes',        { q: '"法鼓" "印順"' }],
    ['notes_or',           'search/notes',        { q: '"波羅蜜" | "波羅密"' }],
    ['notes_not',          'search/notes',        { q: '"迦葉" !"迦葉佛"' }],
    # NEAR 的距離邊界在 5.1.0 改成「相隔 <= n 字」(與說明頁及 KwicService 一致)，
    # 比 Manticore 的「相隔 < n 字」多一個字；intervals 的 _score 不是出現次數，
    # 所以也沒有 total_term_hits。見 doc/elasticsearch-migration.md 的 F-1 第 3b 項。
    # /dev 已在 5.1.0，這一項的 golden 因此是新行為，不再預期 DIFF。
    ['notes_near',         'search/notes',        { q: '"阿含" NEAR/5 "迦葉"' }],
    ['notes_filter_canon', 'search/notes',        { q: '"法鼓"', canon: 'T' }],
    ['notes_facet',        'search/notes',        { q: '"法鼓"', facet: '1' }],
    ['notes_paginate',     'search/notes',        { q: '"法鼓"', start: '20', rows: '5' }],

    # --- 第二期: titles index ---
    # 只比對 num_found: 相關度排序由 Manticore proximity_bm25 換成 Lucene BM25，
    # 順序本來就會不同 (見 doc/elasticsearch-migration.md 的 F-2)。
    ['title_1char',        'search/title',        { q: '經' }],
    ['title_2char',        'search/title',        { q: '法鼓' }],
    ['title_5char',        'search/title',        { q: '觀無量壽經' }],
    ['title_long',         'search/title',        { q: '大般若波羅蜜多經' }],
    ['variants_text',      'search/variants',     { q: '著衣持鉢' }],
    ['variants_title',     'search/variants',     { q: '神咒', scope: 'title' }],

    # --- 第三期: chunks index (search/similar) ---
    # 這幾項預期會 DIFF。/dev 的 similar 還是 Manticore (5.1.0 只搬到 titles)，
    # 因此 golden 是貨真價實的 Manticore 基準。第一階段的 top k 候選由
    # 「Manticore quorum + proximity_bm25」換成「Elasticsearch quorum + Lucene BM25」，
    # 兩種相關度演算法本來就不同，進入 Smith-Waterman 的 500 筆候選不會完全一樣
    # (已定案接受，見 §H 第 2 項)。另外「卷首／卷尾除外」的判斷在舊版是失效的
    # (position_in_juan 沒被 SELECT)，這次一併修正，結果會比舊版多幾筆。
    # 逐筆比對沒有意義，量化差異請用 rake elastic:compare_similar。
    ['similar_gatha',      'search/similar',      { q: '諸惡莫作，眾善奉行，自淨其意，是諸佛教' }],
    ['similar_mind',       'search/similar',      { q: '若人欲了知，三世一切佛，應觀法界性，一切唯心造' }],
    ['similar_moon',       'search/similar',      { q: '菩薩清涼月，遊於畢竟空，垂光照三界，心法無不現。' }],
    ['similar_filter',     'search/similar',      { q: '是日已過，命亦隨減，如少水魚，斯有何樂', canon: 'T' }],
    ['similar_facet',      'search/similar',      { q: '斷愛欲，轉諸結，慢無間等，究竟苦邊', facet: '1' }]
  ].freeze

  # 只保留穩定、可比對的欄位，避免 fixture 太大或被無關變動影響。
  GOLDEN_RESULT_FIELDS = %w[work juan term_hits q hits linehead].freeze

  desc '比較兩個環境的 search/similar 結果重疊率，' \
       '例：rake \'elastic:compare_similar[https://cbdata.dila.edu.tw/dev,http://localhost:3000]\''
  task :compare_similar, %i[base_a base_b] => :environment do |_task, args|
    require 'faraday'
    base_a = args[:base_a].presence || 'https://cbdata.dila.edu.tw/dev'
    base_b = args[:base_b].presence || 'http://localhost:3000'
    puts "A (基準): #{base_a}"
    puts "B (本機): #{base_b}"
    puts

    totals = { a: 0, b: 0, both: 0 }
    SIMILAR_QUERIES.each do |q|
      a = fetch_similar_keys(base_a, q)
      b = fetch_similar_keys(base_b, q)
      next puts format('  %-24s 取得失敗', q.first(12)) if a.nil? || b.nil?

      both = (a & b).size
      totals[:a] += a.size
      totals[:b] += b.size
      totals[:both] += both
      puts format('  %-14s A=%-4d B=%-4d 交集=%-4d 重疊率=%s',
                  "#{q.first(12)}…", a.size, b.size, both,
                  overlap_ratio(both, a.size, b.size))
    end

    puts
    puts format('  合計          A=%-4d B=%-4d 交集=%-4d 重疊率=%s',
                totals[:a], totals[:b], totals[:both],
                overlap_ratio(totals[:both], totals[:a], totals[:b]))
    puts
    puts <<~MSG
      重疊率 = 2 × 交集 / (A + B)。
      第一階段的候選由 Manticore proximity_bm25 換成 Lucene BM25，
      進入 Smith-Waterman 的 top k 不會完全相同，差異無法消除，
      見 doc/elasticsearch-migration.md 的 §F-3 與第三期實作結果。
    MSG
  end

  # compare_similar 用的查詢，取自說明頁 search_similar 的範例。
  SIMILAR_QUERIES = [
    '已得善提捨不證',
    '菩薩清涼月，遊於畢竟空，垂光照三界，心法無不現。',
    '諸惡莫作，眾善奉行，自淨其意，是諸佛教',
    '斷愛欲，轉諸結，慢無間等，究竟苦邊',
    '若人欲了知，三世一切佛，應觀法界性，一切唯心造',
    '是日已過，命亦隨減，如少水魚，斯有何樂'
  ].freeze

  # 一筆結果的識別: 同一個區塊在兩邊的 id 不同 (index 重建過)，
  # 但 work + juan + linehead 唯一決定它在藏經裡的位置。
  def fetch_similar_keys(base, q)
    sleep GOLDEN_REQUEST_INTERVAL
    response = Faraday.get("#{base}/search/similar", q:, cache: '0')
    return nil unless response.success?

    data = JSON.parse(response.body)
    Array(data['results']).map { |row| [row['work'], row['juan'], row['linehead']] }.to_set
  rescue StandardError => e
    puts "    #{e.class}: #{e.message}"
    nil
  end

  def overlap_ratio(both, size_a, size_b)
    total = size_a + size_b
    return 'n/a' if total.zero?

    format('%.1f%%', 200.0 * both / total)
  end

  # 固定檔名。季號不放進檔名: 各環境的 cb.yml 季號不同
  # （production 2026R2、staging 2026R3），用 cb.r 命名會與資料來源不符。
  # 來源與抓取時間記在 JSON 的 _meta 裡。
  def golden_path
    Rails.root.join('test', 'fixtures', 'files', 'search_golden.json')
  end

  # API 有每分鐘的呼叫上限 (見 ApiKeyAuthentication)，連續打會拿到 429，
  # 所以請求之間留間隔，遇到 429 再等久一點重試。
  GOLDEN_REQUEST_INTERVAL = 0.3
  GOLDEN_RETRY_WAIT = 20

  def fetch_golden_case(base, endpoint, params)
    require 'faraday'
    query = params.merge(cache: '0', rows: params[:rows] || '5')

    2.times do |attempt|
      sleep(attempt.zero? ? GOLDEN_REQUEST_INTERVAL : GOLDEN_RETRY_WAIT)
      response = Faraday.get("#{base}/#{endpoint}", query)
      return slim_golden(JSON.parse(response.body)) if response.success?
      return { error: "HTTP #{response.status}" } unless response.status == 429

      puts '    (429 rate limit, 等一下重試)' if attempt.zero?
    end

    { error: 'HTTP 429 (rate limit)' }
  rescue StandardError => e
    { error: "#{e.class}: #{e.message}" }
  end

  def slim_golden(data)
    return { facet_size: data.size, facet: data.first(8) } if data.is_a?(Array)

    out = data.slice('num_found', 'total_term_hits', 'hits', 'possibility').symbolize_keys
    if data['results'].is_a?(Array)
      out[:results] = data['results'].first(5).map do |row|
        row.is_a?(Hash) ? row.slice(*GOLDEN_RESULT_FIELDS) : row
      end
    end
    out[:error] = data['error'].to_s.truncate(120) if data['error'].present?
    out
  end

  def compare_golden(expected, actual)
    return { same: false, message: "錯誤: #{actual[:error]}" } if actual[:error]

    messages = []
    same = true
    %i[num_found total_term_hits hits facet_size].each do |key|
      next if expected[key].nil? && actual[key].nil?

      e = expected[key]
      a = actual[key]
      next if e == a

      same = false
      pct = e.to_f.zero? ? nil : format('%+.2f%%', (a.to_f - e) / e * 100)
      messages << "#{key} #{a} (golden #{e}#{pct ? ", #{pct}" : ''})"
    end

    # 不比對 results 的成員: 排序值平手時，舊版 Manticore 回傳的是不可預期的內部
    # doc id 順序 (見 ElasticQueryBuilder::TIEBREAKER)，當頁成員因此本來就會不同。
    # 這裡只檢查 term_hits 的排序方向有沒有走樣。
    if actual[:results].present?
      hits = actual[:results].filter_map { |row| row['term_hits'] || row[:term_hits] }
      if hits.size > 1 && hits != hits.sort.reverse && expected[:results].present?
        expected_hits = expected[:results].filter_map { |row| row[:term_hits] }
        if expected_hits.size > 1 && expected_hits == expected_hits.sort.reverse
          messages << "term_hits 未遞減: #{hits.inspect}"
          same = false
        end
      end
    end

    { same:, message: same ? '一致' : messages.join('; ') }
  end

  # cat API 的回傳格式依 server 而異 (text 或 JSON)，所以固定要 JSON 自己排版，
  # 不要直接把回傳值當字串處理。
  INDEX_COLUMNS = %w[index docs.count store.size health].freeze

  def print_indices(client)
    # 回傳值是 Elasticsearch::API::Response，取 body 才拿得到真正的 Array。
    rows = client.cat.indices(index: 'cbeta_*', format: 'json', h: INDEX_COLUMNS.join(',')).body
    # 萬一某個 server 仍回傳純文字，就原樣印出，不要讓診斷指令自己爆掉。
    return rows.to_s.each_line { |line| puts "  #{line.chomp}" } unless rows.is_a?(Array)

    rows = rows.sort_by { |row| row['index'].to_s }
    return puts '  (沒有 cbeta_* 開頭的 index)' if rows.empty?

    widths = INDEX_COLUMNS.map do |col|
      [col.size, *rows.map { |row| row[col].to_s.size }].max
    end
    puts "  #{format_index_row(INDEX_COLUMNS, widths)}"
    rows.each { |row| puts "  #{format_index_row(INDEX_COLUMNS.map { row[it].to_s }, widths)}" }
  end

  def format_index_row(values, widths)
    values.each_with_index.map { |value, i| value.ljust(widths[i]) }.join('  ').rstrip
  end

  def index_class(type)
    name = INDEX_CLASSES[type.to_s] or
      abort "未知的 index 種類：#{type}。可用：#{INDEX_CLASSES.keys.join(', ')}"
    name.constantize
  end

  # rake 'elastic:rebuild[notes,cbeta_notes_2026r3_001]' 的引數解析。
  # 為了相容第一期的 rake 'elastic:rebuild[cbeta_text_2026r1_001]'，
  # 第一個引數若不是 index 種類就當成 text 的 index 名稱。
  def resolve_target(args)
    first = args[:type].presence
    if first.nil? || INDEX_CLASSES.key?(first)
      type = first || 'text'
      [type, resolve_index_name(type, args[:index_name])]
    else
      ['text', resolve_index_name('text', first)]
    end
  end

  def resolve_index_name(type, value)
    klass = index_class(type)
    name = value.presence
    name ||= Rails.configuration.x.elasticsearch.index_name if type == 'text'
    abort "請指定 #{type} 的 index 名稱，例如 cbeta_#{type}_2026r3_001。" if name.blank?

    if name == klass.index_alias
      abort "index 名稱不可等於 alias (#{name})。請指定版本化名稱，例如 cbeta_#{type}_2026r3_001。"
    end
    name
  end

  # create_index / rebuild 會先刪掉同名 index。如果那個 index 正是 alias
  # 指向的 (也就是線上查詢正在用的)，重建期間全站搜尋會壞掉，所以先擋下來。
  def refuse_if_live!(type, index_name)
    alias_name = index_class(type).index_alias
    live = begin
      CbetaSearch::ElasticClient.build.indices.get_alias(name: alias_name, ignore_unavailable: true).keys
    rescue StandardError
      []
    end
    return unless live.include?(index_name)

    abort "#{index_name} 正是 alias #{alias_name} 指向的 index，重建它會讓線上搜尋中斷。\n" \
          '請改用新的版本編號建立，完成後再用 rake elastic:promote 切換 alias。'
  end

  def import_xml(type, index_name, xml_path = nil)
    klass = index_class(type)
    xml_path ||= klass.xml_path
    puts "匯入 #{xml_path} 到 #{index_name}"
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    imported = klass.new.import!(xml_path:, index_name:) do |count|
      print "\r  已匯入 #{count} 筆…" if (count % 20_000).zero?
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    puts "\r已匯入 #{imported} 筆到 #{index_name}，耗時 #{format('%.1f', elapsed)} 秒"
  end

  def rebuild_one(type, index_name, xml_path = nil)
    klass = index_class(type)
    refuse_if_live!(type, index_name)

    klass.new.create!(index_name)
    puts "已建立 index：#{index_name}"
    import_xml(type, index_name, xml_path)
    klass.new.promote!(index_name)
    puts "已將 alias #{klass.index_alias} 切到 #{index_name}"
  end

  def elastic_compose_file
    Rails.root.join('compose.elasticsearch.yml')
  end

  def run_elastic_compose!(*args)
    file = elastic_compose_file
    abort "找不到 #{file}" unless file.exist?

    success = system('docker', 'compose', '-f', file.to_s, *args, chdir: Rails.root.to_s)
    abort "docker compose 執行失敗。若使用 Colima，請先執行：colima start --cpu 4 --memory 6" unless success
  end

  def ensure_docker_daemon!
    return if system('docker', 'info', out: File::NULL, err: File::NULL)

    unless system('colima', 'version', out: File::NULL, err: File::NULL)
      abort 'Docker daemon 無法連線，且找不到 Colima。請先啟動 Docker Desktop 或安裝 Colima。'
    end

    puts 'Docker daemon 尚未啟動，正在啟動 Colima…'
    abort 'Colima 啟動失敗' unless system('colima', 'start', '--cpu', '4', '--memory', '6')
  end
end
