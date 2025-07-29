require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module CbData
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

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

    config.cn_filter = %w[TX Y] # 太虛、印順 對 *.cn 屏蔽  
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

    # Search engine 相關
    config.x.se.conf = "/etc/manticoresearch"
    config.x.se.indexes = %w[text notes titles chunks]
    config.x.se.index_text   = "text#{config.cb.v}"
    config.x.se.index_notes  = "notes#{config.cb.v}"
    config.x.se.index_titles = "titles#{config.cb.v}"
    config.x.se.index_chunks = "chunks#{config.cb.v}"

    # Manticore ngram_chars: 要做 ngram 的字元清單
    # 不能大範圍列 U+3000..U+2FA1F, 因為不能與 charset_table 重複, 否則建 index 時會有錯誤。
    #
    # 2025-07-24 CBETA 決議 把「□」和「▆」當作一般文字，不忽略。
    #   * “□” (U+25A1) 表示此處應該有字，但編書的人也不知道是什麼字，就印出一個空白方塊「□」。
    #   * XML unclear 元素 轉成各版用字會使用 “▆” (U+2586) 字元，
    #     這是 CBETA 認為書中文字難以辨識，例如影印古籍，但此處有污損或蟲蛀。
    config.x.se.ngram_chars = "cjk, U+2580..U+25FF, U+2F00..U+A4CF, U+F900..U+FAFF, U+FE30..U+FE4F, U+20000..U+2FA1F"
  end
end
