require 'test_helper'

class BatchWorkersTest < ActiveSupport::TestCase
  test 'development 以外未指定 workers 時用一半的核心, 至少 1 個' do
    with_nprocessors(8) { assert_equal 4, BatchWorkers.count(nil) }
    with_nprocessors(1) { assert_equal 1, BatchWorkers.count(nil) }
    # rake 參數沒給時是 nil, 給空字串 (例: check:docx[T01,]) 也要套預設
    with_nprocessors(8) { assert_equal 4, BatchWorkers.count('') }
  end

  test 'development 未指定 workers 時用全部核心' do
    with_env('development') do
      with_nprocessors(8) { assert_equal 8, BatchWorkers.count(nil) }
    end
  end

  test '指定 workers 時照用, 但限制在 1..64' do
    assert_equal 3, BatchWorkers.count('3')
    assert_equal 1, BatchWorkers.count('0')
    assert_equal 64, BatchWorkers.count(100)
  end

  test '降到 nice 19, fork 出的 child 會繼承' do
    # 在 child 裡做, 不要把跑 test 的 process 也降下去
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      BatchWorkers.lower_priority!
      grandchild = fork { exit!(Process.getpriority(Process::PRIO_PROCESS, 0)) }
      Process.wait(grandchild)
      writer.write($?.exitstatus)
      exit!(0)
    end
    writer.close
    Process.wait(pid)

    assert_equal '19', reader.read
  end

  private

  def with_env(name)
    original = Rails.env
    Rails.env = name
    yield
  ensure
    Rails.env = original
  end

  # 這個專案的 minitest 沒有載入 stub, 自己暫時換掉 Etc.nprocessors
  def with_nprocessors(count)
    original = Etc.method(:nprocessors)
    Etc.define_singleton_method(:nprocessors) { count }
    yield
  ensure
    Etc.define_singleton_method(:nprocessors, original)
  end
end
