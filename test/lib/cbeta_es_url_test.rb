# frozen_string_literal: true

require 'test_helper'

# Elasticsearch 連線 URL 一律用 IP literal，不用 localhost。
#
# 原因是量出來的: sakya 上 TCPSocket 連 localhost 穩定要 50.5 ms、連 127.0.0.1
# 是 0.0 ms —— /etc/hosts 只有 A record，AAAA 落到 DNS 查不到，
# 而 Ruby 3.4 起的 Happy Eyeballs v2 每次連線都會為此等滿 50 ms 的 Resolution Delay。
# 這筆固定成本會被「一次查詢打好幾次 ES」的 endpoint 放大成秒級延遲
# (異體字建議一次 16~31 次)，所以這個轉換不能被改壞。
class CbetaEsUrlTest < ActiveSupport::TestCase
  test 'localhost 換成 127.0.0.1' do
    assert_equal 'http://127.0.0.1:9200', CbetaEsUrl.normalize('http://localhost:9200')
  end

  test '保留 path 與 userinfo' do
    # URI#host= 會把 userinfo 清掉，接了帳密的 ES 會靜默變成連不上
    assert_equal 'http://127.0.0.1:9200/', CbetaEsUrl.normalize('http://localhost:9200/')
    assert_equal 'http://u:p@127.0.0.1:9200', CbetaEsUrl.normalize('http://u:p@localhost:9200')
  end

  test '其他 host 原樣不動' do
    %w[http://127.0.0.1:9200 https://es.example.com:9200 http://es-node1:9200].each do |url|
      assert_equal url, CbetaEsUrl.normalize(url)
    end
  end

  test '不是合法 URL 就原樣回傳，不要讓 app 開不起來' do
    assert_equal 'not a url::', CbetaEsUrl.normalize('not a url::')
    assert_equal '', CbetaEsUrl.normalize('')
  end

  test '實際接上 config 的值不是 localhost' do
    assert_no_match(/localhost/, Rails.configuration.x.elasticsearch.url)
  end
end
