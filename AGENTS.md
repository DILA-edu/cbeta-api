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
- 新 code 在可行範圍內力求符合 RuboCop 風格。
- 不要僅為了符合風格,就要求重構無關的 legacy code。
- 編輯 legacy code 時,除非有要求,否則盡量減少不必要的重構。
- 保持 code 乾淨、易讀、易維護。

## 說明風格
- 以繁體中文說明邏輯。
- 簡潔但實用。
- 在有幫助時提供範例。
