# Install Sphinx Search 3.3.1 on Ubuntu 20.04

## 移除 sphinx2

如果之前有安裝 Sphinx 2, 先移除:

    sudo apt-get remove sphinxsearch

## 下載說明文件、設定檔

參考: <https://github.com/psilocyberunner/sphinxsearch-v3-install>

下載設定檔
    cd ~/git-repos
    git clone git@github.com:psilocyberunner/sphinxsearch-v3-install.git

以下說明中 ~/git-repos/sphinxsearch-v3-install 簡稱 $SRC

## Download Sphinx Search 3.3.1

下載： <http://sphinxsearch.com/downloads/current/>
檔案放在 ~/temp/sphinx-3.3.1-b72d67b-linux-amd64.tar.gz
解壓縮：
    cd ~/temp
    tar zxf sphinx-3.3.1-b72d67b-linux-amd64.tar.gz

Create user to run SphinxSearch

    sudo useradd -r -U -c 'Sphinxsearch system user' sphinx

複製程式

    $ sudo cp sphinx-3.3.1/bin/* /usr/bin
    $ which searchd
    /usr/bin/searchd

Create paths we need to store indexes, config files, logs and etc.

    sudo mkdir -p /etc/sphinx /var/run/sphinx /var/log/sphinx /var/lib/sphinx/data

設權限

    sudo chown -R sphinx:sphinx /etc/sphinx /var/run/sphinx /var/log/sphinx /var/lib/sphinx
    sudo chmod g+w -R /etc/sphinx /var/run/sphinx /var/log/sphinx /var/lib/sphinx

Configuration

`$SRC/etc/sphinx/sphinx.conf` 複製到主機上: `/etc/sphinx/`

`$SRC/lib/systemd/system/sphinx.service` 複製到主機上 `/usr/lib/systemd/system/`

`$SRC/usr/lib/tmpfiles.d/sphinx.conf` 複製到主機上 `/usr/lib/tmpfiles.d/`

Enable systemd service:

    $ sudo systemctl enable sphinx
    Created symlink /etc/systemd/system/sphinx.service → /lib/systemd/system/sphinx.service.
    Created symlink /etc/systemd/system/multi-user.target.wants/sphinx.service → /lib/systemd/system/sphinx.service.

Start the service

    sudo service sphinx start

Check installation
    $ ps ax | grep searchd
    8013 ?        S      0:00 /usr/bin/searchd --config /etc/sphinx/sphinx.conf
    8014 ?        Sl     0:00 /usr/bin/searchd --config /etc/sphinx/sphinx.conf
    8057 pts/1    S+     0:00 grep --color=auto searchd

檢查 mysql 介面
    $ mysql -uroot -h 127.0.0.1 -P 9306

進入 mysql console, 執行 show tables;

    mysql> show tables;
    +-------+------+
    | Index | Type |
    +-------+------+
    | news  | rt   |
    +-------+------+
    1 row in set (0.00 sec)

reboot 之後檢查

    sudo reboot now
    sudo service sphinx status

$ cd /etc/sphinx

準備好 base.conf, 1-cbdata.conf, 1-titles.conf, 1-notes.conf

準備 /etc/sphinx/merge.rb 將多個 conf 檔合併為一個 sphinx.conf

    s = ''
    Dir["*.conf"].each do |f|
      next if f == 'sphinx.conf' or f == 'base.conf'
      puts f
      s += File.read(f) + "\n"
    end
    s += File.read('base.conf')
    File.write('sphinx.conf', s)

執行 merge.rb

    cd /etc/sphinx
    ruby merge.rb

index

    sudo indexer --config /etc/sphinx/sphinx.conf --all

mysql 測試

    $ mysql -h0 -P9306
    mysql> show tables;
    +------------+-------+
    | Index      | Type  |
    +------------+-------+
    | cbeta1     | local |
    | notes1     | local |
    | news       | rt    |
    | titles1    | local |
    +------------+-------+
    4 rows in set (0.00 sec)
