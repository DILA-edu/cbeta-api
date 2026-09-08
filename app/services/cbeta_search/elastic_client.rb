require 'elasticsearch'

module CbetaSearch
  # Elasticsearch client 的建構點。
  # 連線設定見 config/application.rb 的 config.x.elasticsearch。
  class ElasticClient
    def self.build
      Elasticsearch::Client.new(
        url: Rails.configuration.x.elasticsearch.url,
        request_timeout: Rails.configuration.x.elasticsearch.request_timeout,
        retry_on_failure: 2,
        transport_options: {
          request: { timeout: Rails.configuration.x.elasticsearch.request_timeout }
        }
      )
    end
  end
end
