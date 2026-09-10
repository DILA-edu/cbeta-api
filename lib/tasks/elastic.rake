# Elasticsearch text index 的建立、匯入與 alias 切換。
# 見 doc/elasticsearch-migration.md
namespace :elastic do
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
    puts "index_name:  #{conf.index_name}"
    puts "index_alias: #{conf.index_alias}"
    puts "text_xml:    #{conf.text_xml}"

    client = CbetaSearch::ElasticClient.build
    puts "\nindices:"
    print_indices(client)
    puts "\naliases:"
    aliases = client.indices.get_alias(name: conf.index_alias, ignore_unavailable: true)
    if aliases.empty?
      puts "  #{conf.index_alias} 尚未指向任何 index"
    else
      aliases.each_key { |index| puts "  #{conf.index_alias} -> #{index}" }
    end
  rescue StandardError => e
    abort "讀取 Elasticsearch 資訊失敗 (#{conf.url})：#{e.class}: #{e.message}"
  end

  desc '建立 text index，例：rake elastic:create_index[cbeta_text_2026r1_001]'
  task :create_index, [:index_name] => :environment do |_task, args|
    index_name = resolve_index_name(args[:index_name])
    refuse_if_live!(index_name)
    CbetaSearch::TextIndex.new.create!(index_name)
    puts "已建立 index：#{index_name}"
  end

  desc '匯入 text.xml，例：rake elastic:import_text[cbeta_text_2026r1_001]'
  task :import_text, [:index_name, :xml_path] => :environment do |_task, args|
    index_name = resolve_index_name(args[:index_name])
    xml_path = args[:xml_path].presence || Rails.configuration.x.elasticsearch.text_xml
    import_text_xml(index_name, xml_path)
  end

  desc '把 alias 切到指定 index，例：rake elastic:promote[cbeta_text_2026r1_001]'
  task :promote, [:index_name] => :environment do |_task, args|
    index_name = resolve_index_name(args[:index_name])
    alias_name = Rails.configuration.x.elasticsearch.index_alias
    CbetaSearch::TextIndex.new.promote!(index_name, alias_name:)
    puts "已將 alias #{alias_name} 切到 #{index_name}"
  end

  desc '建立 index、匯入 text.xml、切換 alias'
  task :rebuild, [:index_name, :xml_path] => :environment do |_task, args|
    index_name = resolve_index_name(args[:index_name])
    refuse_if_live!(index_name)
    xml_path = args[:xml_path].presence || Rails.configuration.x.elasticsearch.text_xml

    CbetaSearch::TextIndex.new.create!(index_name)
    puts "已建立 index：#{index_name}"
    import_text_xml(index_name, xml_path)
    CbetaSearch::TextIndex.new.promote!(index_name)
    puts "已將 alias #{Rails.configuration.x.elasticsearch.index_alias} 切到 #{index_name}"
  end

  desc '檢查 analyzer 輸出，例：rake elastic:analyze[阿含]'
  task :analyze, [:text] => :environment do |_task, args|
    text = args[:text].presence || '阿含'
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
    puts '註: 若本機 data/manticore-xml/text.xml 與 golden 來源不同季，差異會落在資料版本上。'
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
    ['sc',                 'search/sc',           { q: '观世音' }]
  ].freeze

  # 只保留穩定、可比對的欄位，避免 fixture 太大或被無關變動影響。
  GOLDEN_RESULT_FIELDS = %w[work juan term_hits].freeze

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

  def resolve_index_name(value)
    name = value.presence || Rails.configuration.x.elasticsearch.index_name
    alias_name = Rails.configuration.x.elasticsearch.index_alias
    if name == alias_name
      abort "index 名稱不可等於 alias (#{name})。請指定版本化名稱，例如 cbeta_text_2026r1_001，" \
            '或設定環境變數 CBETA_ES_INDEX_NAME。'
    end
    name
  end

  # create_index / rebuild 會先刪掉同名 index。如果那個 index 正是 alias
  # 指向的 (也就是線上查詢正在用的)，重建期間全站搜尋會壞掉，所以先擋下來。
  def refuse_if_live!(index_name)
    alias_name = Rails.configuration.x.elasticsearch.index_alias
    live = begin
      CbetaSearch::ElasticClient.build.indices.get_alias(name: alias_name, ignore_unavailable: true).keys
    rescue StandardError
      []
    end
    return unless live.include?(index_name)

    abort "#{index_name} 正是 alias #{alias_name} 指向的 index，重建它會讓線上搜尋中斷。\n" \
          '請改用新的版本編號建立，完成後再用 rake elastic:promote 切換 alias。'
  end

  def import_text_xml(index_name, xml_path)
    puts "匯入 #{xml_path} 到 #{index_name}"
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    imported = CbetaSearch::TextIndex.new.import!(xml_path:, index_name:) do |count|
      print "\r  已匯入 #{count} 卷…" if (count % 2000).zero?
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    puts "\r已匯入 #{imported} 卷到 #{index_name}，耗時 #{format('%.1f', elapsed)} 秒"
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
