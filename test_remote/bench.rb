# 全文檢索效能量測，不屬於 `bin/rails test`。
#
#   ruby test_remote/bench.rb dev stable   # 兩邊交錯跑，控掉時段差異
#   ruby test_remote/bench.rb dev          # 只跑一邊
#   ruby test_remote/bench.rb compare A.json [B.json ...]
#
# 或用 rake:
#   rake remote:bench[dev,stable]
#   rake remote:bench[compare,tmp/bench/a.json,tmp/bench/b.json]
#
# 結果寫到 tmp/bench/（已 gitignore），compare 可以拿舊檔案跟新檔案對比，
# 例如「優化前 / 優化後 / Manticore」三欄。
#
# 量的是 API 自報的處理時間（回應的 time 欄位），不含網路往返；
# wall 也一併記下來，兩者的差距就是網路加 Rails 的額外成本。
#
# rate limit 與 API key 的處理與 test_remote/run.rb 相同，見該檔說明。
# 從校外跑一定要設 CBETA_RATE_LIMIT，否則幾百個請求必定撞 429：
#
#   CBETA_RATE_LIMIT=54 rake remote:bench[dev,stable]
require 'faraday'
require 'fileutils'
require 'json'

module Bench
  APIS = {
    'dev' => 'https://cbdata.dila.edu.tw/dev',
    'stable' => 'https://cbdata.dila.edu.tw/stable',
    'test' => 'http://cbdata.dila.edu.tw/test',
    'local' => 'http://localhost:3000'
  }.freeze

  OUT_DIR = File.expand_path('../tmp/bench', __dir__)

  # 每組 1 次 cold + (REPS-1) 次 warm，取 warm 的中位數
  REPS = 5

  RATE_WINDOW = 60
  RATE_LIMIT = ENV.fetch('CBETA_RATE_LIMIT', 0).to_i
  MAX_RETRY = 2

  # 有 Rails.cache 的 endpoint（all_in_one / similar / variants）一律帶 cache=0，
  # 量的是引擎的真實運算成本，不是快取命中。
  #
  # kind:
  #   :same —— 兩邊做同一件事、語法相同，倍率有意義
  #   :differ —— 語法語意在新舊版不同（見 doc/elasticsearch-migration.md），
  #              只看各自的延遲，不做倍率比較
  CASES = [
    ['基本檢索 /search', '常見詞「菩薩」', 'search', { q: '菩薩', rows: 10 }, :same],
    ['基本檢索 /search', '長詞「阿耨多羅三藐三菩提」', 'search', { q: '阿耨多羅三藐三菩提', rows: 10 }, :same],
    ['基本檢索 /search', '罕見詞「鬱多羅僧」', 'search', { q: '鬱多羅僧', rows: 10 }, :same],
    ['基本檢索 /search', '中頻詞「如是我聞」', 'search', { q: '如是我聞', rows: 10 }, :same],
    ['多字詞 /search/extended', '空白分隔「般若 波羅蜜」', 'search/extended', { q: '般若 波羅蜜', rows: 10 }, :same],
    ['分類統計 /search/facet', 'category（q=菩薩）', 'search/facet/category', { q: '菩薩' }, :same],
    ['夾注檢索 /search/notes', '夾注「菩薩」', 'search/notes', { q: '菩薩', rows: 10 }, :same],
    ['夾注檢索 /search/notes', '夾注「梵語」', 'search/notes', { q: '梵語', rows: 10 }, :same],
    ['經名檢索 /search/title', '經名「觀無量壽經」', 'search/title', { q: '觀無量壽經', rows: 10 }, :same],
    ['經名檢索 /search/title', '經名「金剛般若波羅蜜經」', 'search/title', { q: '金剛般若波羅蜜經', rows: 10 }, :same],
    ['簡轉繁 /search/sc', '簡轉繁「观无量寿经」', 'search/sc', { q: '观无量寿经' }, :same],
    ['異體字 /search/variants', '異體字「無上正等正覺」', 'search/variants', { q: '無上正等正覺', cache: 0 }, :same],
    ['異體字 /search/variants', '異體字「大比丘三千威儀」', 'search/variants', { q: '大比丘三千威儀', cache: 0 }, :same],
    ['異體字 /search/variants', '異體字「阿耨多羅三藐三菩提」', 'search/variants', { q: '阿耨多羅三藐三菩提', cache: 0 }, :same],
    ['相似句 /search/similar', '相似句「一切有為法如夢幻泡影」', 'search/similar',
     { q: '一切有為法如夢幻泡影', rows: 10, cache: 0 }, :same],
    ['相似句 /search/similar', '相似句「諸行無常是生滅法」', 'search/similar',
     { q: '諸行無常是生滅法', rows: 10, cache: 0 }, :same],
    ['整合查詢 /search/all_in_one', '整合查詢「菩薩」', 'search/all_in_one', { q: '菩薩', rows: 10, cache: 0 }, :same],
    ['整合查詢 /search/all_in_one', 'Exclude「"菩薩" -"諸菩薩"」', 'search/all_in_one',
     { q: '"菩薩" -"諸菩薩"', rows: 10, cache: 0 }, :same],
    ['整合查詢 /search/all_in_one', 'NEAR「"法鼓" NEAR/7 "迦葉"」', 'search/all_in_one',
     { q: '"法鼓" NEAR/7 "迦葉"', rows: 10, cache: 0 }, :same],
    ['整合查詢 /search/all_in_one', 'NEAR「"阿含" NEAR/5 "迦葉"」', 'search/all_in_one',
     { q: '"阿含" NEAR/5 "迦葉"', rows: 10, cache: 0 }, :same],

    # 以下語法在新舊版的語意不同，不做倍率比較
    ['語法差異 /search/extended', 'Exclude 後搭配「"菩薩" -"菩薩摩訶薩"」', 'search/extended',
     { q: '"菩薩" -"菩薩摩訶薩"', rows: 10 }, :differ],
    ['語法差異 /search/extended', 'Exclude 前搭配「"菩薩" -"諸菩薩"」', 'search/extended',
     { q: '"菩薩" -"諸菩薩"', rows: 10 }, :differ],
    ['語法差異 /search/extended', 'Exclude「"阿耨多羅三藐三菩提" -"得阿耨多羅三藐三菩提"」', 'search/extended',
     { q: '"阿耨多羅三藐三菩提" -"得阿耨多羅三藐三菩提"', rows: 10 }, :differ],
    ['語法差異 /search/extended', 'NOT「"菩薩" !"佛"」', 'search/extended', { q: '"菩薩" !"佛"', rows: 10 }, :differ],
    ['語法差異 /search/extended', 'OR「"般若" | "波羅蜜"」', 'search/extended', { q: '"般若" | "波羅蜜"', rows: 10 }, :differ],
    ['語法差異 /search/extended', 'NEAR「"菩薩" NEAR/7 "佛"」', 'search/extended',
     { q: '"菩薩" NEAR/7 "佛"', rows: 10 }, :differ]
  ].freeze

  class << self
    def run(envs)
      envs.each { |e| abort "不認得的 server: #{e}（可用 #{APIS.keys.join(' / ')}）" unless APIS.key?(e) }

      @request_times = []
      started = Time.now
      puts "量測對象: #{envs.map { |e| "#{e} (#{APIS[e]})" }.join('、')}"
      puts "每組 #{REPS} 次（1 cold + #{REPS - 1} warm），" \
           "節流: #{RATE_LIMIT.positive? ? "#{RATE_LIMIT} req/min" : '關閉（校內 IP 已豁免）'}"

      total = CASES.size * REPS * envs.size
      done = 0
      cases = CASES.map do |group, label, path, params, kind|
        entry = { group:, label:, path:, params:, kind:, runs: envs.to_h { |e| [e, []] } }
        REPS.times do |rep|
          # 交錯順序，免得某一邊固定吃到暖機或時段差異
          (rep.even? ? envs : envs.reverse).each do |env|
            r = fetch(env, path, params).merge(rep:)
            entry[:runs][env] << r
            done += 1
            printf("\r[%d/%d] %-28s %-6s rep%d  %s", done, total, label[0, 26], env, rep,
                   r[:api_time] ? format('%.3fs', r[:api_time]) : "HTTP #{r[:http]}")
          end
        end
        entry
      end
      puts

      write(envs:, started:, cases:)
    end

    def compare(files)
      runs = files.flat_map do |path|
        data = JSON.parse(File.read(path), symbolize_names: true)
        name = File.basename(path, '.json')
        data[:meta][:envs].map { |env| [+"#{env}@#{name}", env.to_sym, data] }
      end
      abort '沒有可比較的資料' if runs.empty?

      print_table(runs, :same)
      print_table(runs, :differ)
      print_consistency(runs)
    end

    private

    def fetch(env, path, params)
      url = "#{APIS[env]}/#{path}"
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = api_get(url, params)
      wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      row = { http: response.status, wall:, bytes: response.body.to_s.bytesize }

      body = JSON.parse(response.body)
      if body.is_a?(Array) # facet 回傳 array
        row.merge(num_found: body.size)
      else
        row.merge(
          api_time: body['time'], num_found: body['num_found'],
          total_term_hits: body['total_term_hits'], hits: body['hits'],
          possibility: body['possibility'],
          first_id: body['results'].is_a?(Array) ? body['results'].first&.dig('id') : nil,
          # 舊版 Manticore 的回應會帶 SQL 欄位，新版 Elasticsearch 不會
          engine: body.key?('SQL') ? 'manticore' : 'es'
        )
      end
    rescue StandardError => e
      row.merge(error: "#{e.class}: #{e.message}")
    end

    def api_get(url, params)
      headers = { 'Referer' => ENV.fetch('CBETA_REFERER', 'ray@dila.edu.tw') }
      key = ENV['CBETA_API_KEY']
      headers['Authorization'] = "Bearer #{key}" if key

      response = nil
      (MAX_RETRY + 1).times do |attempt|
        throttle!
        response = Faraday.get(url, params, headers) { |req| req.options.timeout = 300 }
        return response unless response.status == 429
        break if attempt == MAX_RETRY

        wait = (response.headers['Retry-After'] || RATE_WINDOW).to_i + 1
        puts "\n429 rate limit，等 #{wait} 秒後重試: #{url}"
        sleep(wait)
        @request_times.clear
      end
      response
    end

    # 與 run.rb 相同的 sliding window：保證任何 60 秒內不超過 RATE_LIMIT 次
    def throttle!
      return if RATE_LIMIT <= 0

      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      drop_expired(now)
      if @request_times.size >= RATE_LIMIT
        wait = RATE_WINDOW - (now - @request_times.first) + 0.1
        sleep(wait) if wait.positive?
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        drop_expired(now)
      end
      @request_times << now
    end

    def drop_expired(now)
      @request_times.shift while @request_times.first && (now - @request_times.first) >= RATE_WINDOW
    end

    def write(envs:, started:, cases:)
      FileUtils.mkdir_p(OUT_DIR)
      path = File.join(OUT_DIR, "#{envs.join('-')}-#{started.strftime('%Y%m%d-%H%M%S')}.json")
      meta = {
        envs:, reps: REPS,
        version: File.read(File.expand_path('../VERSION', __dir__)).strip,
        started_at: started.strftime('%Y-%m-%d %H:%M:%S'),
        finished_at: Time.now.strftime('%Y-%m-%d %H:%M:%S')
      }
      File.write(path, JSON.pretty_generate({ meta:, cases: }))
      puts "結果: #{path}"
      failed = cases.sum { |c| c[:runs].values.flatten.count { |r| r[:http] != 200 } }
      puts "非 200 的請求: #{failed} 次" if failed.positive?
      path
    end

    # runs: [[顯示用名稱, env, 整份資料], ...]
    def print_table(runs, kind)
      rows = CASES.select { |c| c[4] == kind }
      return if rows.empty?

      puts
      puts(kind == :same ? '== 同功能比較（中位數）==' : '== 語法語意不同，僅列各自延遲 ==')
      printf("%-34s %s\n", '查詢', runs.map { |name, _, _| name[0, 18].rjust(19) }.join)
      rows.each do |_, label, _, _, _|
        values = runs.map { |_, env, data| median_of(data, label, env) }
        printf("%-34s %s\n", label[0, 32],
               values.map { |v| (v ? format('%.3fs', v) : '—').rjust(19) }.join)
      end
    end

    def print_consistency(runs)
      puts
      puts '== 結果一致性（num_found）=='
      CASES.each do |_, label, _, _, _|
        found = runs.map { |_, env, data| find_case(data, label)&.dig(:runs, env, 0, :num_found) }
        mark = found.uniq.size == 1 ? '✓' : '△'
        printf("%s %-34s %s\n", mark, label[0, 32], found.map { |f| f.to_s.rjust(19) }.join)
      end
    end

    def find_case(data, label)
      data[:cases].find { |c| c[:label] == label }
    end

    # warm（第 2 次以後）的中位數，取 API 自報時間；沒有 time 欄位就退回 wall
    def median_of(data, label, env)
      runs = find_case(data, label)&.dig(:runs, env)
      return nil if runs.nil? || runs.size < 2

      warm = runs[1..].map { |r| r[:api_time] || r[:wall] }.compact
      median(warm)
    end

    def median(values)
      return nil if values.empty?

      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end
  end
end

if ARGV.first == 'compare'
  files = ARGV[1..]
  abort '用法: ruby test_remote/bench.rb compare A.json [B.json ...]' if files.empty?
  Bench.compare(files)
else
  Bench.run(ARGV.empty? ? %w[dev] : ARGV)
end
