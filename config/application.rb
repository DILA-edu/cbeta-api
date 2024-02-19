require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module CBData
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.0
    config.cb = config_for(:cb)

    config.cn_filter = %w[TX Y] # 太虛、印順 對 *.cn 屏蔽  
    config.x.figure_url = 'https://raw.githubusercontent.com/cbeta-git/CBR2X-figures/master'
    config.time_zone = 'Taipei'

    config.x.authority = File.join(config.cb.git, 'Authority-Databases')
    config.cbeta_xml   = File.join(config.cb.git, 'cbeta-xml-p5a')
    config.cbeta_data  = File.join(config.cb.git, 'cbeta-metadata')
    config.cbeta_gaiji = File.join(config.cb.git, 'cbeta_gaiji')
    config.x.figures   = File.join(config.cb.git, 'CBR2X-figures')
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
    config.x.se.conf = "/etc/mancitoresearch"
    config.x.se.indexes = %w[text notes titles chunks]
    config.x.se.index_text   = "text#{config.cb.v}"
    config.x.se.index_notes  = "notes#{config.cb.v}"
    config.x.se.index_titles = "titles#{config.cb.v}"
    config.x.se.index_chunks = "chunks#{config.cb.v}"
  end
end
