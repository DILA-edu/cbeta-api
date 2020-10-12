# Goto

## 一、經卷結構

* 跳到 大正藏 第一經： /juans/goto?canon=T&work=1
* 跳到 大正藏 第一經 第二卷： /juans/goto?canon=T&work=1&juan=2
* 跳到 大正藏 第一經 第12頁： /juans/goto?canon=T&work=1&page=12
* 跳到 大正藏 第一經 第11頁 中欄 第10行： /juans/goto?canon=T&work=1&page=11&col=b&line=10

## 二、書本結構

* 跳到 大正藏 第一冊： /juans/goto?canon=T&vol=1
* 跳到 大正藏 第一冊 第12頁： /juans/goto?canon=T&vol=1&page=12
* 跳到 大正藏 第一冊 第11頁 中欄 第10行： /juans/goto?canon=T&vol=1&page=11&col=b&line=10

## 三、使用 linehead 參數

### （一）指定行首資訊

例如： <http://cbdata.dila.edu.tw/v1.2/juans/goto?linehead=T01n0001_p0066c25>

### （二）指定 CBETA 引用格式資訊

要先將引用資訊 escape，例如「CBETA, T01, no. 1, p. 67, a13」escape 成為「CBETA,%20T01,%20no.%201,%20p.%2067,%20a13」。

例如： <http://cbdata.dila.edu.tw/v1.2/juans/goto?linehead=CBETA,%20T01,%20no.%201,%20p.%2067,%20a13>

CBETA 2017 新引用格式

* 單行：CBETA, T30, no. 1579, p. 279a7
* 跨行：CBETA, T30, no. 1579, p. 279a7-23
* 跨欄：CBETA, T30, no. 1579, p. 279a7-b23
* 跨頁：CBETA, T30, no. 1579, pp. 279a7-280b26

CBETA 2019 新引用格式

例如： <http://cbdata.dila.edu.tw/v1.2/juans/goto?linehead=CBETA%202019.Q3,%20T01,%20no.%201,%20p.%2067,%20a13>

* 單行：CBETA 2019.Q3, T30, no. 1579, p. 279a7
* 跨行：CBETA 2019.Q3, T30, no. 1579, p. 279a7-23
* 跨欄：CBETA 2019.Q3, T30, no. 1579, p. 279a7-b23
* 跨頁：CBETA 2019.Q3, T30, no. 1579, pp. 279a7-280b26

### （三）論文慣用引用格式

* [T51, no. 2087, pp. 868-888](http://cbdata.dila.edu.tw/v1.2/juans/goto?linehead=T51,%20no.%202087,%20pp.%20868-888)
* [T46, no. 1911, p. 18c](http://cbdata.dila.edu.tw/v1.2/juans/goto?linehead=T46,%20no.%201911,%20p.%2018c)
* [T2, no. 150A, p. 878a24](http://cbdata.dila.edu.tw/v1.2/juans/goto?linehead=T2,%20no.%20150A,%20p.%20878a24)
* [T15, no. 602, p. 64a14-b26.](http://cbdata.dila.edu.tw/v1.2/juans/goto?linehead=T15,%20no.%20602,%20p.%2064a14-b26.)
* [T15, no. 606, pp. 215c22-216a2.](http://cbdata.dila.edu.tw/v1.2/juans/goto?linehead=T15,%20no.%20606,%20pp.%20215c22-216a2.)
* [《大正藏》冊47，第1969 號](http://cbdata.dila.edu.tw/v1.2/juans/goto?linehead=%E3%80%8A%E5%A4%A7%E6%AD%A3%E8%97%8F%E3%80%8B%E5%86%8A47%EF%BC%8C%E7%AC%AC1969%20%E8%99%9F)
* [《大正藏》冊47，第1970 號，卷6](http://cbdata.dila.edu.tw/v1.2/juans/goto?linehead=%E3%80%8A%E5%A4%A7%E6%AD%A3%E8%97%8F%E3%80%8B%E5%86%8A47%EF%BC%8C%E7%AC%AC1970%20%E8%99%9F%EF%BC%8C%E5%8D%B76)
* [《大正藏》冊19，第974C 號，頁386](http://cbdata.dila.edu.tw/v1.2/juans/goto?linehead=%E3%80%8A%E5%A4%A7%E6%AD%A3%E8%97%8F%E3%80%8B%E5%86%8A19%EF%BC%8C%E7%AC%AC974C%20%E8%99%9F%EF%BC%8C%E9%A0%81386)
* [《大正藏》冊55，第2154 號，頁565a](http://cbdata.dila.edu.tw/v1.2/juans/goto?linehead=%E3%80%8A%E5%A4%A7%E6%AD%A3%E8%97%8F%E3%80%8B%E5%86%8A55%EF%BC%8C%E7%AC%AC2154%20%E8%99%9F%EF%BC%8C%E9%A0%81565a)
* [《續藏經》冊142，頁1003b](http://cbdata.dila.edu.tw/v1.2/juans/goto?linehead=%E3%80%8A%E7%BA%8C%E8%97%8F%E7%B6%93%E3%80%8B%E5%86%8A142%EF%BC%8C%E9%A0%811003b)
* [R130, p. 861b7](http://cbdata.dila.edu.tw/v1.2/juans/goto?linehead=R130,%20p.%20861b7)

### （四）快速代碼

例如代碼 DA1 可以跳到 T01n0001_p0001b11： <http://cbdata.dila.edu.tw/v1.2/juans/goto?linehead=DA1>

代碼 SN1.1 可以跳到 N13n0006_p0001a12： <http://cbdata.dila.edu.tw/v1.2/juans/goto?linehead=SN1.1>

常用的北傳四阿含與南傳四尼科耶代碼如下：

* SA 《雜阿含》
* MA 《中阿含》
* DA 《長阿含》
* EA 《增壹阿含》
* SN 《相應部》
* MN 《中部》
* DN 《長部》
* AN 《增支部》

完整的代碼對照表請看： <https://github.com/DILA-edu/cbeta-metadata/blob/master/goto/goto-list.txt>
