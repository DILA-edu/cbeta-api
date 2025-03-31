source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.4.2'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 7.2.2'
# Use sqlite3 as the database for Active Record
gem 'sqlite3', '~> 1.4'
# Use Puma as the app server
gem 'puma', '~> 3.11'
# Use SCSS for stylesheets
gem 'sass-rails', '~> 5.0'
# Use Uglifier as compressor for JavaScript assets
gem 'uglifier', '>= 1.3.0'
# Use CoffeeScript for .coffee assets and views
gem 'coffee-rails', '~> 5.0.0'
# See https://github.com/rails/execjs#readme for more supported runtimes
#gem 'therubyracer', platforms: :ruby

# 第一次進到網站，上方工具沒有作用，要 reload 才會恢復
# 不知道是不是 turbolinks 造成？
# Turbolinks makes navigating your web application faster. Read more: https://github.com/turbolinks/turbolinks
#gem 'turbolinks', '~> 5'

# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder'

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', '>= 1.1.0', require: false

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
end

group :development do
  # Access an interactive console on exception pages or by calling 'console' anywhere in the code.
  gem 'web-console', '>= 3.3.0'
  gem 'listen', '~> 3.3'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring'
  gem 'spring-watcher-listen'
end

group :test do
  # Adds support for Capybara system testing and selenium driver
  gem 'capybara', '>= 2.15'
  gem 'selenium-webdriver'
  # Easy installation and use of web drivers to run system tests with browsers
  #gem 'webdrivers'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
#gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]

# 如果剛更新 cbeta gem
# bundle install 錯誤: could not be found in any of the sources listed in your Gemfile
# 可以執行以下命令從 RubyGems 取得最新清單
# bundle --full-index
gem 'cbeta', '>= 3.5.5'

gem "haml-rails"
gem 'time_diff'
#gem 'zhongwen_tools'
gem 'chronic_duration'
gem 'mysql2'

group :production, :cn do
  gem 'pg'
  gem "dalli" # for memcached
end

group :development do
  gem 'capistrano-rails'
  gem 'capistrano-asdf'
  gem 'capistrano-passenger'
end

gem 'dartsass-sprockets'
gem "autoprefixer-rails"

gem 'rubyzip'
gem 'colorize'
gem 'diff-lcs'
gem 'unihan2', '>= 1.0.0'
gem 'open3'
gem 'faraday'
gem 'csv', '~> 3.3', '>= 3.3.2'
gem "rswag-ui"
gem 'will_paginate', '~> 4.0'
gem 'will_paginate-bootstrap-style'
gem "git", "~> 3.0"

# fix error: cannot load such file -- net/smtp
gem 'net-smtp', require: false
gem 'net-imap', require: false
gem 'net-pop', require: false
