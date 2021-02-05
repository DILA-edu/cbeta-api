# mirror site 所需磁碟空間

一套 約 24 GB

* Rails 程式及各種格式資料：15 GB
* PostgreSQL Database: 6 GB
* CBETA XML: 2.2 GB
* Sphinx Index (含標點）：419 MB
* Sphinx Index: 383 MB
* CBETA 缺字資料: 44 MB
* CBETA Metadata: 22 MB

兩套 48 GB

以上統計不含：
* kwic 一套約 63 GB
* dia.dila.edu.tw 圖檔 約 431 GB (佛寺志、大正藏、嘉興藏)

## 查看 PostgreSQL database size

    $ sudo su - postgres
    $ psql
    SELECT pg_database.datname, 
      pg_size_pretty(pg_database_size(pg_database.datname)) AS size 
      FROM pg_database;

## 查看 Sphinx Index Size

    $ cd /var/lib/sphinxsearch
    $ du -hs data7
    $ du -hs data7-puncs