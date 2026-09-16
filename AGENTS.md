# AGENTS.md

## 語言
- 一律使用繁體中文回應。
- 所有 IT 與技術術語保持英文(例如 controller、model、migration、callback)。
- 所有 code 一律使用英文。

## Rails 準則
- 本專案使用 Rails 8.1。
- 在可行範圍內遵循 Rails 慣例。
- 優先採用標準 Rails 模式與最佳實踐。
- 複雜的 business logic 優先使用 service object。
- 避免 fat controller。

## 程式碼風格
- 新撰寫的 code 優先遵循 Ruby 與 Rails 社群慣例。
- 新 code 在可行範圍內力求符合 RuboCop 風格; 提交前跑 `bin/rubocop` 檢查。
- 不要僅為了符合風格,就要求重構無關的 legacy code。
- 編輯 legacy code 時,除非有要求,否則盡量減少不必要的重構。
- 保持 code 乾淨、易讀、易維護。
- RuboCop 設定見 `.rubocop.yml`(Rails omakase 為底)。legacy 的 Layout/Style offense
  已凍結在 `.rubocop_todo.yml`, 不要為了消除它們而重構; Lint 類刻意不凍結,
  輸出裡剩下的是待人工判斷的項目。

## 說明風格
- 以繁體中文說明邏輯。
- 簡潔但實用。
- 在有幫助時提供範例。
