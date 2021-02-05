# 考慮是否更新 ruby 及 rails 的版本

## 開發端 Mac

### 安裝 Homebrew

### 安裝 rvm

    \curl -sSL https://get.rvm.io | bash -s stable

### 安裝 Ruby

參考 [Install Ruby on Rails 5.2 · macOS High Sierra](http://railsapps.github.io/installrubyonrails-mac.html)

安裝新版本 ruby 例：

    rvm install 2.7.2
    rvm --default use 2.7.2

### Check the Gem Manager

    gem -v
    gem update --system

### RVM’s Global Gemset

    rvm gemset use global
    gem update

### Faster Gem Installation

    echo "gem: --no-document" >> ~/.gemrc

### Install Bundler

    gem install bundler

### Install Nokogiri

把 nokogiri 安裝在 global gemset 裡：

    gem install nokogiri

### install mysql2

    brew install openssl
    brew install mysql
    gem install mysql2

### 安裝 Rails

如果要更新到 Rails 6.0.2.2

    rvm use ruby-2.7.2@cbdata14 --create
    gem install rails -v 6.0.3.4

修改 .rvm-version, .ruby-gemset 裡的版本號碼。

修改 Gemfile

    gem 'rails', '~> 6.0.3'

bundle

    bundle update
    rails -v

編輯 config/deploy/production.rb 設定正確的 ruby 版本及 gemset

    set :rvm_ruby_version, '2.7.2@cbdata14'

### The Update Task

參考 [Upgrading Ruby on Rails](https://guides.rubyonrails.org/upgrading_ruby_on_rails.html)

    rails app:update

### capistrano 設定

編輯 config/deploy.rb

    set :application, 'cbdata14'
    set :repo_url, 'git@gitlab.com:cbdata/cbdata13'

### 把 application 放上 gitlab

在 gitlab group: cbdata 裡建立 project

在 local 端將 rails app project 初始化為 git repository

    cd [ProjectRoot]
    git init

確認 .gitignore 設定

push

    git add .
    git commit -m 'first commit'
    git remote add origin git@gitlab.com:cbdata/cbdata13.git
    git push -u origin master

## server 設定 rvm, ruby, rails

install ruby

    rvm install 2.7.2
    rvm --default use 2.7.2
    gem update --system

RVM’s Global Gemset

    rvm gemset use global
    gem update
    gem install nokogiri

install rails

    rvm use ruby-2.7.2@cbdata14 --create
    gem install rails -v 6.0.3.4
    rvm use 2.7.2@cbdata14 --default
    rails -v
    gem install pg
