source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '2.7.2'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 6.0.3'
# Use sqlite3 as the database for Active Record
gem 'sqlite3'
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

# Use jquery as the JavaScript library
gem 'jquery-rails'

# 第一次進到網站，上方工具沒有作用，要 reload 才會恢復
# 不知道是不是 turbolinks 造成？
# Turbolinks makes navigating your web application faster. Read more: https://github.com/turbolinks/turbolinks
#gem 'turbolinks', '~> 5'

# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 2.5'
# Use Redis adapter to run Action Cable in production
# gem 'redis', '~> 3.0'
# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Use Capistrano for deployment
#gem 'capistrano-rails', group: :development

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
  gem 'spring-watcher-listen', '~> 2.0.0'
end

group :test do
  # Adds support for Capybara system testing and selenium driver
  gem 'capybara', '>= 2.15'
  gem 'selenium-webdriver'
  # Easy installation and use of web drivers to run system tests with browsers
  gem 'webdrivers'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
#gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]

# 如果剛更新 cbeta gem
# bundle install 錯誤: could not be found in any of the sources listed in your Gemfile
# 可以執行以下命令從 RubyGems 取得最新清單
# bundle --full-index
gem 'cbeta', '>= 2.7.11'

gem "haml-rails", "~> 2.0"
gem 'time_diff'
gem 'zhongwen_tools'
gem 'chronic_duration'
gem 'mysql2'

group :production do
  gem 'pg'
  gem "dalli" # for memcached
end

group :development do
  gem 'capistrano-rails'
  gem 'capistrano-asdf'
  gem 'capistrano-passenger'
end

#source 'https://rails-assets.org' do
#  gem 'rails-assets-bootstrap'
#end
gem 'bootstrap', '~> 4.0.0'

gem 'rubyzip'
gem 'colorize'
#gem 'rack-cors', require: 'rack/cors'
gem 'runbook'
gem 'diff-lcs'
gem 'unihan2', '>= 0.2.0'