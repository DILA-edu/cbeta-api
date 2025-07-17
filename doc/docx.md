# xml for docx

1. xml4docx1
   將 CBETA XML 簡化為適合 docx 使用
   rake 'convert:xml4docx1[2025-07,T]'
2. xml4docx2
   將 xml4docx1 結果 做 扁平化 處理，如例：seg 包 seg
   rake 'convert:xml4docx2[T]'
3. check:xml4docx
   檢查 xml4docx 正確性
   rake check:xml4docx
4. 給 heven 比對 text 正確性
