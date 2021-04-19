# eBook 電子書

下載 heaven 做好的 PDF, MOBI

* curl -C - -O https://archive.cbeta.org/download/pdf_a4/cbeta_pdf_1_2021q2.zip
* curl -C - -O https://archive.cbeta.org/download/pdf_a4/cbeta_pdf_2_2021q2.zip
* curl -C - -O https://archive.cbeta.org/download/pdf_a4/cbeta_pdf_3_2021q2.zip
* curl -C - -O https://archive.cbeta.org/download/mobi/cbeta_mobi_2021q1.zip

rename

* mv cbeta_mobi_2021q2.zip cbeta-mobi-2021q2.zip
* mv cbeta_pdf_1_2021q2.zip cbeta-pdf-2021q2-1.pdf
* mv cbeta_pdf_2_2021q2.zip cbeta-pdf-2021q2-2.pdf
* mv cbeta_pdf_3_2021q2.zip cbeta-pdf-2021q2-3.pdf

unzip

* unzip cbeta-mobi-2021q2.zip
* unzip cbeta-pdf-2021q2-1.zip
* unzip cbeta-pdf-2021q2-2.zip
* unzip cbeta-pdf-2021q2-3.zip

清除 舊資料

* rm -rf mobi
* rm -rf pdf

合併 資料夾

* mv cbeta_mobi_2021q2 mobi
* mv cbeta_pdf_1_2021q2 pdf
* mv cbeta_pdf_2_2021q2/* pdf
* mv cbeta_pdf_3_2021q2/* pdf
* rm -r cbeta_pdf_2_2021q2
* rm -r cbeta_pdf_3_2021q2
