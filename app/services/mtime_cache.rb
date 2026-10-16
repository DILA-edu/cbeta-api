# 以檔案 mtime + size 為失效條件的 process 內快取。
#
# 用於每個 request 都要 parse 的靜態檔 (詞典、openapi.yaml 等)。
# 季度更新資料時不一定會重啟 app, 所以不能只在開機時讀一次:
# 依賴的檔案一有變動就重新產生。
#
# 快取的值會被多個 request 共用, 呼叫端不可修改它。
# 能凍結的請在 block 裡凍結 (例如 JSON.parse(s, freeze: true)), 誤改時才會立刻出錯。
module MtimeCache
  @entries = {}
  @mutex = Mutex.new

  class << self
    # key: 快取名稱; paths: 依賴的檔案, 任一檔變動就重新執行 block
    def fetch(key, *paths)
      stamp = paths.map { |p| File.stat(p).then { [ it.mtime, it.size ] } }

      entry = @mutex.synchronize { @entries[key] }
      return entry[:value] if entry && entry[:stamp] == stamp

      # 不在 lock 內產生, 以免慢的 block 擋住其他 key。
      # 同時有多個 thread 重算同一 key 時結果相同, 最後寫入的留下即可。
      value = yield
      @mutex.synchronize { @entries[key] = { stamp:, value: } }
      value
    end

    def clear
      @mutex.synchronize { @entries.clear }
    end
  end
end
