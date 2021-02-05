# Remove Old Version

## PostgreSQL

執行 psql

    sudo su - postgres
    psql

list all database

    \l

移除舊 database

    drop database xxx;

list all user

    \du

移除舊 user

    drop user pg_xxx;

## Ubuntu

刪除 舊版 server account

    sudo deluser --remove-home [UserName]
