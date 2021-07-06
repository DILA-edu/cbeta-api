# PostgreSQL

## add server local user

已經建過了的話，不必每季做。

新增資料庫 user (密碼參考 server 上 config/database.yml)

    sudo adduser pgcbapi

## Postgre Console

change to the postgres unix user

    sudo su - postgres

執行 `psql`

### create database user

如果建過了，不必每季做.

假設密碼設為 MyPassword, 下面會用到

執行

    create user pgcbapi with password 'MyPassword';
    ALTER USER pgcbapi CREATEDB;

要給 create database 的權限，才能執行 rake db:reset。（如果沒有 create database 權限，db:reset 在 create database 時會失敗，但是好像也沒關係，因為它還是重建所有 table，而且在 create database 之前，通常 drop database 就會失敗了，因為有其他 connection 存在。）

### create database

    create database cbdata1;
    create database cb_analytics;
    grant all privileges on database cbdata1 to pgcbapi;
    grant all privileges on database cb_analytics to pgcbapi;
    ALTER DATABASE cbdata1 OWNER TO pgcbapi;
    ALTER DATABASE cb_analytics OWNER TO pgcbapi;

執行 `\q` 離開 PostgreSQL console.

執行 `exit` 切換為原 user

測試連線

    sudo su - pgcbapi
    psql -d cbdata1 -U pgcbapi

成功後，輸入 `\q` 離開 psql，輸入 `exit` 切換回原 user。

## database.yml

編輯 /var/www/cbdata1/shared/config/database.yml

    production:
        primary:
            adapter: postgresql
            encoding: unicode
            database: cbdata1
            host: localhost
            pool: 5
            username: pgcbapi
            password: MyPassword
        analytics:
            adapter: postgresql
            encoding: unicode
            database: cb_analytics
            host: localhost
            pool: 5
            username: pgcbapi
            password: MyPassword
            migrations_paths: db/analytics_migrate

注意上面的 MyPassword 要取代為真正的密碼。

## disk usage

查看 database 佔用的磁碟空間

    sudo su - postgres 
    psql
    postgres=# SELECT pg_database_size('cbdata13');
