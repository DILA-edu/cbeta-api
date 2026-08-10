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

def get_html(params)
  r = get_json("juans", params)
  refute_nil(r)
  r['results'].first
end

def get_json(base_url, params={})
  url = "#{$api}/#{base_url}"
  response = Faraday.get(url, params, headers)
  if response.status == 200
    JSON.parse(response.body)
  end
end

def get_text(url, params={})
  url = "#{$api}/#{url}"
  r = Faraday.get(url, params, headers)
  if r.status == 200
    r.body.force_encoding("UTF-8")
  else
    puts "\nurl: #{url}"
    abort "get_text 發生錯誤"
  end
end

def headers
  { 'Referer' => $referer }
end

$env = ARGV.first
$api = case $env
when 'stable' then 'https://cbdata.dila.edu.tw/stable'
when 'cn'     then 'https://api.cbetaonline.cn'
when 'local'  then 'http://localhost:3000'
when 'test'   then 'http://cbdata.dila.edu.tw/test'
else 
  $env = 'dev'
  'https://cbdata.dila.edu.tw/dev'
end
puts "Test API: #{$api}"
