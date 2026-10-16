# frozen_string_literal: true

require 'etc'

# 多 process 批次工作的共用設定。
# 這類工作會在 production 所在的 server 上跑, 要讓位給線上服務。
module BatchWorkers
  module_function

  # 未指定 workers 時只用一半的核心, 另一半留給 production;
  # development 是自己的機器, 沒有線上服務要讓, 用全部核心
  def count(workers)
    (workers.presence || default_count).to_i.clamp(1, 64)
  end

  def default_count
    Rails.env.development? ? Etc.nprocessors : [ Etc.nprocessors / 2, 1 ].max
  end

  # 把目前 process 降到最低 CPU 優先權 (nice 19), 之後 fork 的 worker 會繼承。
  # CPU 有空檔時照常全速跑, production 需要時就讓出去。
  # 注意: 降了就升不回來, 在 rails console 呼叫的話整個 console 都會變成 nice 19。
  def lower_priority!
    Process.setpriority(Process::PRIO_PROCESS, 0, 19)
  end

  # 把 items 交錯分給 workers 個 child process (fork)，各自執行 block，
  # 回傳每個 worker 的結果 (依 worker 順序)。block 的回傳值以 JSON 經 pipe 傳回。
  #
  # 交錯分配 (i % workers) 讓各 worker 拿到的檔案大小較平均。
  # block 收到 (slice, index)，index 為 0 的 worker 可負責印進度。
  def fork_map(items, workers, symbolize_names: false)
    slices = items.group_by.with_index { |_item, i| i % workers }.values
    $stdout.flush
    # child 不可共用 parent 的 DB 連線
    ActiveRecord::Base.connection_handler.clear_all_connections!

    readers = slices.each_with_index.map do |slice, index|
      reader, writer = IO.pipe
      pid = fork do
        reader.close
        writer.write(JSON.generate(yield(slice, index)))
        writer.close
        exit!(0)
      end
      writer.close
      [ pid, reader ]
    end

    # 先讀完 pipe 再等 child 結束, 避免 pipe buffer 塞滿造成 deadlock
    outputs = readers.map { |_pid, reader| reader.read.tap { reader.close } }
    readers.each_with_index do |(pid, _reader), index|
      _pid, status = Process.wait2(pid)
      # 原本直接 parse, child 異常結束時只會看到看不出原因的 JSON::ParserError
      raise "batch worker #{index} 異常結束: #{status}" unless status.success?
    end
    outputs.map { JSON.parse(it, symbolize_names:) }
  end
end
