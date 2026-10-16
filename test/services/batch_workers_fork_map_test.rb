require 'test_helper'

# fork 前會清掉 DB 連線 (child 不可共用), 會中斷 transactional test 的 transaction
class BatchWorkersForkMapTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test '交錯分配給各 worker, 依 worker 順序回傳結果' do
    r = BatchWorkers.fork_map((1..7).to_a, 3) { |slice, index| { 'index' => index, 'items' => slice } }

    assert_equal([ [ 1, 4, 7 ], [ 2, 5 ], [ 3, 6 ] ], r.map { it['items'] })
    assert_equal([ 0, 1, 2 ], r.map { it['index'] })
  end

  test 'symbolize_names' do
    r = BatchWorkers.fork_map(%w[a b], 2, symbolize_names: true) { |slice, _index| { count: slice.size } }
    assert_equal [ { count: 1 }, { count: 1 } ], r
  end

  test 'child 異常結束時回報是哪個 worker, 而不是 JSON 解析錯誤' do
    error = assert_raises(RuntimeError) do
      capture_io do
        BatchWorkers.fork_map([ 1, 2 ], 2) { |_slice, index| index == 1 ? exit!(3) : [] }
      end
    end
    assert_match(/batch worker 1 異常結束/, error.message)
  end

  test '結果夠大時也不會因 pipe buffer 卡住' do
    r = BatchWorkers.fork_map([ 1, 2 ], 2) { |_slice, _index| 'x' * 200_000 }
    assert_equal [ 200_000, 200_000 ], r.map(&:size)
  end
end
