# 從 github 取得 cbeta xml p5a

第一次 clone

    cd ~/git-repos
    git clone git@github.com:cbeta-git/xml-p5a.git cbeta-xml-p5a

切換到某個版本，例如 2017 Q4:

    git checkout tags/CBETA2017Q4

如果要切換到某個 commit:

    git checkout 7c76cb2

如果要切換到最新的 commit:

    git checkout master

之後如果要更新

    cd ~/git-repos/cbeta-xml-p5a
    git pull
