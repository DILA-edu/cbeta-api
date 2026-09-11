# 遠端 API 測試 (staging / production)，不屬於 `bin/rails test`。
#
# 全部測試:   ruby test_remote/run.rb dev
# 只測試部分: ruby test_remote/run.rb dev kwic
#
# 或用 rake (會自動帶入 config.cbeta_xml):
#   rake remote:test[dev]
#   rake remote:test[dev,kwic]
require 'faraday'
require 'fileutils'
require 'minitest/autorun'
require 'nokogiri'

require 'minitest/reporters'
Minitest::Reporters.use!

# CBETA XML (p5a) 目錄，少數 test 需要用它逐一檢查所有典籍。
# 未設定時，相關 test 會 skip。
XML = ENV['CBETA_XML']

# 測試過程中產生的檔案放這裡 (Rails 專案的 tmp 已被 gitignore)
TMP_DIR = File.expand_path('../tmp/test_remote', __dir__)
FileUtils.mkdir_p(TMP_DIR)

module Minitest
  module Assertions
    # 修改預設的 message, 避免列印整卷 html
    def message msg = nil, ending = nil, &default
      proc {
        msg = msg.call.chomp(".") if Proc === msg
        if msg.nil? or msg.to_s.empty?
          "#{default.call}#{ending || "."}"
        else
          "#{msg}"
        end
      }
    end
  end
end

if ARGV.size < 2
  Dir[File.join(__dir__, 'test_*.rb')].sort.each do |f|
    puts "require: #{File.basename(f)}"
    require f
  end
else
  s = File.join(__dir__, "test_#{ARGV[1]}.rb")
  puts "require: #{File.basename(s)}"
  require s
end

$referer = ENV.fetch('CBETA_REFERER', 'ray@dila.edu.tw')

# 有 key 時額度從 60/min/IP 提高到 300/min/user。
# rake remote:test 用 exec，環境變數會直接傳進來。
API_KEY = ENV['CBETA_API_KEY']

# --- rate limit 因應（見 app/controllers/concerns/api_key_authentication.rb）---
#
# server 對未帶 key 的 request 限 60/min/IP、帶有效 key 限 300/min/user。
# 本套件的請求量遠超過這個上限（光 test_goto_works 就對全藏每部典籍各打一次，
# 約 4000 次），不節流的話大多數 test 都會拿到 429。
#
# 節流採 sliding window：保證「任何 60 秒內」不超過額度，因此也涵蓋 server
# 端的 fixed window。只有逼近上限時才等待，小範圍的測試
# （例如 rake remote:test[dev,juan]）仍然全速跑完。
RATE_WINDOW = 60

# 留 10% 餘裕：client 與 server 的 window 邊界不會對齊，額度也可能與
# 其他來源（瀏覽器、同事）共用同一個 IP。
# 與別人共用對外 IP 時可用 CBETA_RATE_LIMIT 再調低。
RATE_LIMIT = (ENV['CBETA_RATE_LIMIT'] || ((API_KEY ? 300 : 60) * 0.9).floor).to_i

# 真的撞到 429 時的重試次數（等待時間以 server 回的 Retry-After 為準）
MAX_RETRY = 2

$request_times = []

# 逼近每分鐘上限時才擋下來等待
def throttle!
  now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  drop_expired(now)

  if $request_times.size >= RATE_LIMIT
    wait = RATE_WINDOW - (now - $request_times.first) + 0.1
    sleep(wait) if wait.positive?
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    drop_expired(now)
  end

  $request_times << now
end

def drop_expired(now)
  $request_times.shift while $request_times.first && (now - $request_times.first) >= RATE_WINDOW
end

# 所有打到 API 的 request 都走這裡，統一節流與 429 重試。
def api_get(url, params = {}, extra_headers = {})
  h = headers.merge(extra_headers)
  response = nil

  (MAX_RETRY + 1).times do |attempt|
    throttle!
    response = Faraday.get(url, params, h)
    return response unless response.status == 429
    break if attempt == MAX_RETRY

    wait = (response.headers['Retry-After'] || RATE_WINDOW).to_i + 1
    puts "\n429 rate limit，等 #{wait} 秒後重試: #{url}"
    sleep(wait)
    # 已經等過一整個 window，先前記錄的時間都失效了
    $request_times.clear
  end

  response
end

def get_html(params)
  get_json('juans', params)['results'].first
end

def get_json(base_url, params = {})
  url = "#{$api}/#{base_url}"
  response = api_get(url, params)
  assert_http_ok(response, url, params)
  JSON.parse(response.body)
end

def get_text(url, params = {})
  url = "#{$api}/#{url}"
  r = api_get(url, params)
  assert_http_ok(r, url, params)
  r.body.force_encoding('UTF-8')
end

# 非 200 就直接讓該 test 失敗並印出 status。
# 舊版是回 nil（get_text 則是 abort 中斷整個 run），
# 結果 429 會以 "undefined method '[]' for nil" 的形式爆在各個 test 裡，
# 完全看不出真正原因。
def assert_http_ok(response, url, params)
  return if response.status == 200

  body = response.body.to_s[0, 200]
  flunk "GET #{url} #{params.inspect} → HTTP #{response.status}\n#{body}"
end

def headers
  h = { 'Referer' => $referer }
  h['Authorization'] = "Bearer #{API_KEY}" if API_KEY
  h
end

$env = ARGV.first
$api = case $env
when 'stable' then 'https://cbdata.dila.edu.tw/stable'
when 'local'  then 'http://localhost:3000'
when 'test'   then 'http://cbdata.dila.edu.tw/test'
else 
  $env = 'dev'
  'https://cbdata.dila.edu.tw/dev'
end
puts "Test API: #{$api}"
puts "API key: #{API_KEY ? '有' : '無（設 CBETA_API_KEY 可提高額度）'}，" \
     "節流上限 #{RATE_LIMIT} req/min"
