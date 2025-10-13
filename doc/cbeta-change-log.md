# Create CBETA Change Log

## 製作 change log

參考 lib/tasks/quarterly/runbook-change-log.rb

## 匯入 RDB

設定 cb.yml
  changelog: '/Users/ray/Documents/Projects/CBETA/changelog'

be rake 'import:changelog[2025R2]'