Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  config.x.v = '2'
  config.x.ver = '1.2.26.13'
  config.x.q = '2021q3' # 季號

  GIT = '/Users/ray/git-repos'
  config.x.git       = GIT
  config.cbeta_xml   = File.join(GIT, 'cbeta-xml-p5a')
  config.cbeta_data  = File.join(GIT, 'cbeta-metadata')
  config.cbeta_gaiji = File.join(GIT, 'cbeta_gaiji')
  config.x.authority = File.join(GIT, 'Authority-Databases')
  config.x.figures   = File.join(GIT, 'CBR2X-figures')
  config.x.word_seg  = File.join(GIT, 'word-seg')
  config.x.seg_bin   = File.join(GIT, 'word-seg', 'bin')
  config.x.seg_model = Rails.root.join('data', 'crf-model', 'all')

  d = '/Volumes/Ray-3TB/cbeta-api/kwic25'
  config.kwic_base = Dir.exist?(d) ? d : Rails.root.join('data', 'kwic25')
  
  config.sphinx_index = "cbeta"
  config.x.sphinx_titles = "titles"
  config.x.sphinx_footnotes = 'footnotes'
  
  config.log_level = :debug

  # In the development environment your application's code is reloaded on
  # every request. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable/disable caching. By default caching is disabled.
  # Run rails dev:cache to toggle caching.
  if Rails.root.join('tmp', 'caching-dev.txt').exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true

    config.cache_store = :memory_store
    config.public_file_server.headers = {
      'Cache-Control' => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false

    config.cache_store = :null_store
  end

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false

  config.action_mailer.perform_caching = false

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Debug mode disables concatenation and preprocessing of assets.
  # This option may cause significant delays in view rendering with a large
  # number of complex assets.
  config.assets.debug = true

  # Suppress logger output for asset requests.
  config.assets.quiet = true

  # Raises error for missing translations.
  # config.action_view.raise_on_missing_translations = true

  # Use an evented file watcher to asynchronously detect changes in source code,
  # routes, locales, etc. This feature depends on the listen gem.
  config.file_watcher = ActiveSupport::EventedFileUpdateChecker
end
