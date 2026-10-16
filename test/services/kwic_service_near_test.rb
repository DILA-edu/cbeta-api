require 'test_helper'

# NEAR 單卷搜尋: 第二個詞不在本卷時應視為無結果。
# 過去會走到 sort_by_pos 的 abort (SystemExit), rescue StandardError 接不到。
class KwicServiceNearTest < ActiveSupport::TestCase
  setup do
    @kwic = KwicService.new(Dir.mktmpdir, false)
    @kwic.instance_variable_set(:@option, { work: 'T0001', juan: 1 })
    @kwic.define_singleton_method(:open_files) { |_path| true }
    # 第一個詞在本卷有 2 筆, 第二個詞不在本卷
    @kwic.define_singleton_method(:search_sa_after_open_files) { |q| q == '法鼓' ? [ 0, 2 ] : nil }
    @kwic.define_singleton_method(:sa) { |i| i * 10 }
  end

  test '第二個詞不在本卷時回傳空陣列' do
    assert_equal [], @kwic.send(:search_near_juan, '"法鼓" NEAR/5 "迦葉"')
  end

  test '第一個詞不在本卷時回傳空陣列' do
    assert_equal [], @kwic.send(:search_near_juan, '"迦葉" NEAR/5 "法鼓"')
  end

  test 'sort_by_pos 收到 nil 時丟 StandardError 而非 SystemExit' do
    assert_raises(ArgumentError) { @kwic.send(:sort_by_pos, nil, nil) }
  end
end
