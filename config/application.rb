require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# 由 text index 的 alias 推導其他 index 的 alias。
#
# 慣例是 <前綴>_<index 種類>_<角色>，例如 production 的 cbeta_text_current
# 與 staging 的 cbeta_text_staging。這樣既有的 cb.yml 只設一個 index_alias
# 就能涵蓋全部 index，需要各自指定時再用 elasticsearch.aliases 覆寫。
#
# 定義在這裡而不是 app/services: config/application.rb 執行時 autoload 還沒啟動。
module CbetaEsAlias
  TYPES = %i[text notes titles chunks].freeze

  def self.build(text_alias, overrides = {})
    TYPES.index_with { |type| overrides[type].presence || derive(text_alias, type) }.freeze
  end

  def self.derive(text_alias, type)
    return text_alias if type == :text

    m = text_alias.to_s.match(/\A(.*)_text(_.*)?\z/)
    return "#{text_alias}_#{type}" if m.nil?

    "#{m[1]}_#{type}#{m[2]}"
  end
end

module CbData
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    
    config.cb = config_for(:cb)

    # 版號單一來源:根目錄的 VERSION 檔(方便人工與 script 讀寫)
    config.x.ver = Rails.root.join('VERSION').read.strip
    config.cn_filter = %w[TX Y] # 太虛、印順 對 *.cn 屏蔽

    # --- API key 控管（見 doc/api-key-design.md 3）---
    #
    # 未帶 key 也放行的 Origin 白名單。比對 Origin 完整字串
    # （scheme + host [+ port]），不做 subdomain 模糊比對。
    #
    # 白名單放 config/cb.yml（該檔 gitignored、每台機器一份），不進版控 ——
    # 2026-08-21 主管指示。因此每台機器要自己維護，見 doc/api-key-design.md 3.3。
    #
    # ⚠️ cb.yml 沒有這個 key 時就是空陣列。過渡期內空陣列不會有事（未帶 key
    #    照樣放行），但過渡期結束後（api_key_required = true）會讓 cbetaonline
    #    前端全站拿到 401。上線前務必用 rake api_key:config 確認。
    config.api_origin_allowlist = Array(config.cb.api_origin_allowlist)

    # 過渡期: false = 未帶 key 也放行（但帶了無效 key 一律 401）。
    # 過渡期結束時改為 true，未帶 key 即回 401。
    # 結束日期待與主管、同仁討論確定（設計文件 11.2）。
    config.api_key_required = false
    config.x.figure_url = 'https://raw.githubusercontent.com/cbeta-git/CBR2X-figures/master'
    config.time_zone = 'Taipei'

    config.x.authority = File.join(config.cb.git, 'Authority-Databases')
    config.cbeta_xml   = File.join(config.cb.git, 'cbeta-xml-p5a')
    config.cbeta_data  = File.join(config.cb.git, 'cbeta-metadata')
    config.cbeta_gaiji = File.join(config.cb.git, 'cbeta_gaiji')
    config.x.figures   = File.join(config.cb.git, 'CBR2X-figures')
    config.x.t2k       = File.join(config.cb.git, 'cbwork-common-T2K', 'TK_head')
    config.x.work_info = File.join(config.x.authority, 'authority_catalog', 'json')
  
    # 分詞相關
    config.x.word_seg  = File.join(config.cb.git, 'word-seg')
    config.x.seg_bin   = File.join(config.cb.git, 'word-seg', 'bin')
    config.x.seg_model = Rails.root.join('data', 'crf-model', 'all')

    # KWIC 相關
    config.x.kwic.base = Rails.root.join('data', 'kwic')
    config.x.kwic.html = File.join(config.x.kwic.base, 'html')
    config.x.kwic.temp = File.join(config.x.kwic.base, 'temp')

    # Elasticsearch
    #
    # 四個 index (text / notes / titles / chunks) 全部由 Elasticsearch 提供，
    # Manticore 已退場，見 doc/elasticsearch-migration.md
    #
    # 連線設定優先讀 config/cb.yml (該檔 gitignored、每台機器一份)，
    # 其次讀環境變數，最後才用本機開發預設值。
    es = config.cb.elasticsearch || {}
    config.x.elasticsearch.url = es[:url] ||
      ENV.fetch('ELASTICSEARCH_URL', 'http://localhost:9200')
    config.x.elasticsearch.request_timeout = (
      es[:request_timeout] || ENV.fetch('ELASTICSEARCH_REQUEST_TIMEOUT', 120)
    ).to_i

    # 查詢一律走 alias，實際 index 為版本化名稱 (例 cbeta_text_2026r1_001)，
    # 重建完成後以 rake elastic:promote 原子切換 alias。
    #
    # index_alias 是 text index 的 alias，同時也是其他 index alias 的推導依據:
    # cbeta_text_current → cbeta_notes_current / cbeta_titles_current / cbeta_chunks_current
    # (staging 是 cbeta_text_staging → cbeta_notes_staging …)。
    # 這讓既有的 cb.yml 不必改就能沿用；要各自指定時在 cb.yml 寫
    #   elasticsearch:
    #     aliases:
    #       notes: cbeta_notes_current
    config.x.elasticsearch.index_alias = es[:index_alias] ||
      ENV.fetch('CBETA_ES_INDEX_ALIAS', 'cbeta_text_current')

    overrides = (es[:aliases] || {}).symbolize_keys
    config.x.elasticsearch.aliases = CbetaEsAlias.build(
      config.x.elasticsearch.index_alias, overrides
    )

    # 建立/匯入 index 時必須指定版本化 index 名稱; 對 alias 名稱建 index 會被 ES 拒絕。
    # 只有 text 有這個預設值，其餘 index 一律要在 rake 引數明確指定。
    config.x.elasticsearch.index_name = es[:index_name] ||
      ENV.fetch('CBETA_ES_INDEX_NAME', config.x.elasticsearch.index_alias)

    # ES 匯入來源: 既有 Manticore 轉檔流程產出的 xmlpipe2 檔案
    xml_dir = Rails.root.join('data', 'search-xml')
    config.x.elasticsearch.xml = {
      text: xml_dir.join('text.xml'),
      notes: xml_dir.join('notes.xml'),
      titles: xml_dir.join('titles.xml'),
      chunks: xml_dir.join('chunks.xml')
    }
    # 舊名，仍有文件與 rake 引數在用
    config.x.elasticsearch.text_xml = config.x.elasticsearch.xml[:text]
  end
end
