require 'test_helper'

class IntToZhtTest < ActiveSupport::TestCase
  test '轉成中文數字' do
    {
      0 => '零', 1 => '一', 10 => '十', 11 => '十一', 20 => '二十', 99 => '九十九',
      100 => '一百', 101 => '一百零一', 110 => '一百一十', 115 => '一百一十五',
      210 => '二百一十', 600 => '六百', 1000 => '一千', 1001 => '一千零一',
      1010 => '一千零一十', 1100 => '一千一百'
    }.each do |num, expected|
      assert_equal expected, IntToZht.convert(num), num.to_s
    end
  end
end
