require 'test_helper'

class JuanLineTest < ActiveSupport::TestCase
  # X1546 的卷序與頁碼順序不同: 第 3 卷 (0154a01) 在冊內排在第 2 卷 (0163b01) 之前
  setup do
    [ [ 1, '0147a01' ], [ 2, '0163b01' ], [ 3, '0154a01' ] ].each do |juan, lb|
      JuanLine.create!(vol: 'X78', work: 'X1546', juan:, lb:, uuid: "x1546-#{juan}")
    end
  end

  test 'get_juan_by_vol_work_lb 依 lb 判斷所在的卷, 不依建立順序' do
    assert_equal 1, JuanLine.get_juan_by_vol_work_lb('X78', 'X1546', '0150a01')
    assert_equal 3, JuanLine.get_juan_by_vol_work_lb('X78', 'X1546', '0160a01')
    assert_equal 2, JuanLine.get_juan_by_vol_work_lb('X78', 'X1546', '0165a01')
    assert_nil JuanLine.get_juan_by_vol_work_lb('X78', 'X1546', '0100a01')
  end
end
