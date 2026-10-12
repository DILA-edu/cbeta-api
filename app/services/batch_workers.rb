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
end
