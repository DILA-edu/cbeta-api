# Mac

## mysql2

$ brew info mysql 
    Installed
    /opt/homebrew/Cellar/mysql/9.0.1

$ gem install mysql2 -- --with-mysql-dir=/opt/homebrew/Cellar/mysql/9.0.1

如果出現錯誤
    ld: library 'zstd' not found
執行
    $ gem install mysql2 -v '0.5.6' -- --with-opt-dir=$(brew --prefix openssl) --with-ldflags=-L/opt/homebrew/opt/zstd/lib

## crf++

brew install crf++

## trang

$ brew install openjdk
$ echo 'export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"' >> ~/.zshrc
$ brew install jing-trang
