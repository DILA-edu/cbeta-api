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

  # 卷跨冊時一冊一段 (L1557 卷 17: L130 0876b01 → L131 0001a01)。
  # 原本只記得後半段: 卷的起點變成 L131 0001a01, L130 後段被判成卷 16
  def create_cross_volume_juans
    JuanLine.create!(vol: 'L130', work: 'L1557', juan: 16, seq: 1, lb: '0815a01', uuid: 'l1557-16')
    JuanLine.create!(vol: 'L130', work: 'L1557', juan: 17, seq: 1, lb: '0876b01', uuid: 'l1557-17')
    JuanLine.create!(vol: 'L131', work: 'L1557', juan: 17, seq: 2, lb: '0001a01')
    JuanLine.create!(vol: 'L131', work: 'L1557', juan: 18, seq: 1, lb: '0059a01', uuid: 'l1557-18')
  end

  test '卷跨冊: vols 依序列出冊號' do
    create_cross_volume_juans

    assert_equal %w[L130 L131], JuanLine.vols('L1557', 17)
    assert_equal %w[L130], JuanLine.vols('L1557', 16)
  end

  test '卷跨冊: 卷的起點是第一段' do
    create_cross_volume_juans

    assert_equal %w[L130 0876b01], JuanLine.get_first_lb_by_work_juan('L1557', 17)
  end

  test '卷跨冊: 前後兩冊的行都判斷為同一卷' do
    create_cross_volume_juans

    assert_equal 16, JuanLine.get_juan_by_vol_work_lb('L130', 'L1557', '0870a01')
    assert_equal 17, JuanLine.get_juan_by_vol_work_lb('L130', 'L1557', '0880a01')
    assert_equal 17, JuanLine.get_juan_by_vol_work_lb('L131', 'L1557', '0010a01')
    assert_equal 18, JuanLine.get_juan_by_vol_work_lb('L131', 'L1557', '0060a01')
  end
end
