# OpenCC

用於中文簡體轉繁體功能。

參考：[ubuntu安装opencc，简体转繁体](https://blog.51cto.com/12376658/1889594), 2017-01-06

## 下载opencc安装包

https://github.com/BYVoid/OpenCC/releases

下載 OpenCC-ver.1.0.5.tar.gz

## 解压文件

$ tar -zxvf  OpenCC-ver.1.0.5.tar.gz

## opencc 需要安装 cmake, doxygen

$ sudo apt-get install cmake
$ sudo apt-get install doxygen

## 安裝

$ cd OpenCC-ver.1.0.5
$ make
$ sudo make install

## 測試

$ echo '微儿博客简体转繁体' | opencc -c s2tw