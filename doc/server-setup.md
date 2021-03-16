# 新主機 初始設定

OS: Ubuntu 20.04 LTS

## Apache

    sudo apt update
    sudo apt install apache2
    sudo ufw allow in "Apache"

client browser 應該要可以看到 Apache2 Ubuntu Default Page

## asdf + Ruby + Rails

[asdf](https://github.com/asdf-vm/asdf)

安裝 asdf

    git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.8.0

Add the following to ~/.bashrc:
    . $HOME/.asdf/asdf.sh
    . $HOME/.asdf/completions/asdf.bash

登出、再登入，查看 asdf 版本
    asdf version

install the asdf plugin for Ruby:
    asdf plugin add ruby

使用 asdf 安裝 ruby 3.0.0
    asdf install ruby 3.0.0

在 home ~/.tool-versions 檔案裡可以設定預設的 Ruby 版本，也可以使用以下命令：
    asdf global ruby 3.0.0

update
    gem update --system
    gem update

install gems
    gem install nokogiri
    gem install rails -v 6.0.3

## Install NodeJS

參考 <https://github.com/asdf-vm/asdf-nodejs>

install asdf-nodejs plugin:

    asdf plugin-add nodejs https://github.com/asdf-vm/asdf-nodejs.git

Import the Node.js release team's OpenPGP keys to main keyring:

    bash -c '${ASDF_DATA_DIR:=$HOME/.asdf}/plugins/nodejs/bin/import-release-team-keyring'

install nodejs
    asdf install nodejs 14.16.0
    asdf global nodejs 14.16.0

## Passenger

[Passenger Tutorials: Deploy to Production](https://www.phusionpassenger.com/docs/tutorials/deploy_to_production/)

## PostgreSQL

參考 postgresql.md

## Install Sphinx Search

參考 sphinx3-ubuntu20.md

## gem install mysql2

Sphinx Search 要透過 mysql 介面呼叫

    sudo apt-get install libmysqlclient-dev
    gem install mysql2 -v '0.5.3' --source 'https://rubygems.org/'

## 從 Github 取得相關資料

Server 上準備好可以連結 GitHub, GitLab 的 SSH Key.

建立資料夾
    cd /home/ray
    mkdir git-repos
    cd git-repos

Clone from GutHub, GitLab:
    git clone git@github.com:DILA-edu/Authority-Databases.git
    git clone git@github.com:cbeta-git/xml-p5a.git
    mv xml-p5a cbeta-xml-p5a
    git clone git@github.com:DILA-edu/cbeta-metadata.git
    git clone git@github.com:cbeta-org/cbeta_gaiji.git
    git clone git@github.com:cbeta-git/CBR2X-figures.git
    git clone git@gitlab.com:dila/word-seg.git

## Transferring the app code to the server

編輯 config/deploy/staging.rb 裡的 server, deploy_to 設定。

程式碼 上傳 到 server:
    cap staging deploy

## Create Tables

rails db:environment:set RAILS_ENV=production
bundle exec rake db:schema:load DISABLE_DATABASE_ENVIRONMENT_CHECK=1

## Configuring Apache and Passenger

Determine the Ruby command that Passenger should use

    cd /var/www/cbapi1/current
    passenger-config about ruby-command

在結果之中找到這個：

    To use in Apache: PassengerRuby /home/ray/.asdf/installs/ruby/2.7.2/bin/ruby

編輯 /etc/apache2/sites-available/cbeta-api.conf

    Alias /dev /var/www/cbapi1/current/public
    <Location /dev>
        PassengerBaseURI /dev
        PassengerAppRoot /var/www/cbapi1/current
        PassengerRuby /home/ray/.asdf/installs/ruby/2.7.2/bin/ruby
    </Location>
    <Directory /var/www/cbapi1/current/public>
        Allow from all
        Options -MultiViews
        Require all granted
    </Directory>

編輯 /etc/apache2/sites-available/000-default.conf

    <VirtualHost *:80>
      ...
      Include sites-available/cbeta-api.conf
    </VirtualHost>

restart apache2

    sudo service apache2 restart

## HTTPS

參考 [https.md](https.md)

## 從舊主機複製資料

$ screen
$ rsync -vaz ray@cbdata.dila.edu.tw:/var/www/cbdata15/shared/data /var/www/cbapi1/shared/
$ rsync -vaz ray@cbdata.dila.edu.tw:/var/www/cbdata15/shared/public/help /var/www/cbapi1/shared/public
$ rsync -vaz ray@cbdata.dila.edu.tw:/var/www/cbdata15/shared/public/download /var/www/cbapi1/shared/public
$ cd /var/www/cbapi1/shared/public/download
$ rm cbeta-text
$ ln -s text-for-asia-network cbeta-text

## Quarterly

$ bundle exec rake quarterly:run[staging]

## OpenCC

簡體轉繁體的功能會用到 OpenCC:

    sudo apt-get install opencc

測試

    echo '当观色无常' | opencc -c s2tw

## CRF++ for 自動分詞

install

    cd ~/git-repos
    git clone git@github.com:taku910/crfpp.git
    cd crfpp
    ./configure
    sed -i '/#include "winmain.h"/d' crf_learn.cpp
    sed -i '/#include "winmain.h"/d' crf_test.cpp
    make
    sudo make install
    sudo cp ~/git-repos/crfpp/.lib/libcrfpp.so.0 /usr/lib

測試

    $ crf_test -h
    CRF++: Yet Another CRF Tool Kit
    Copyright (C) 2005-2013 Taku Kudo, All rights reserved.
