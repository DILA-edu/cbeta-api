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

  # count_near 靠 near_match? 判斷「這組位置會不會產生 KWIC」，
  # 必須與 read_text_near 回傳 nil 的條件完全一致 (否則計數與 KWIC 筆數會對不上)。
  test 'near_match? 與 read_text_near 是否回傳 nil 一致' do
    kwic = KwicService.new(Dir.mktmpdir, false)
    kwic.instance_variable_set(:@option, { around: 3 })
    # 不含標點的 offset → 含標點的 offset: 模擬中間穿插標點 (每 3 字多 1 個標點)
    to_t2 = ->(o) { o + (o / 3) }
    kwic.define_singleton_method(:suffix_info) do |o|
      { 'vol' => 'T01', 'work' => 'T0001', 'juan' => 1, 'offset_in_text_with_punc' => to_t2.(o) }
    end
    kwic.define_singleton_method(:cache_fetch_juan_text) { |*| 'x' * 500 }
    kwic.define_singleton_method(:read_str_with_punc) { |text, start, size| +text[start, [ size, 0 ].max].to_s }
    kwic.define_singleton_method(:abridge_note) { |s| s }

    rng = Random.new(42)
    terms = %w[法 法鼓 迦葉 般若波羅蜜]
    500.times do
      matches = Array.new(rng.rand(2..4)) do
        { pos_sa: [ rng.rand(10..100), 0 ], term: terms.sample(random: rng) }
      end.sort_by { it[:pos_sa].first }

      expected = !kwic.send(:read_text_near, matches).nil?
      assert_equal expected, kwic.send(:near_match?, matches), matches.inspect
    end
  end

  test 'count_near 與 search_near 的筆數相同' do
    @kwic.define_singleton_method(:search_sa_after_open_files) { |q| { '法鼓' => [ 0, 2 ], '迦葉' => [ 2, 2 ] }[q] }
    # sa: 法鼓在 10、40，迦葉在 13、90 (不含標點的位置)
    positions = [ 10, 40, 13, 90 ]
    @kwic.define_singleton_method(:sa) { |i| positions[i] }
    @kwic.define_singleton_method(:suffix_info) do |o|
      { 'vol' => 'T01', 'lb' => '0001a01', 'work' => 'T0001', 'juan' => 1, 'offset_in_text_with_punc' => o }
    end
    @kwic.define_singleton_method(:cache_fetch_juan_text) { |*| 'x' * 200 }
    @kwic.define_singleton_method(:read_str_with_punc) { |text, start, size| +text[start, [ size, 0 ].max].to_s }
    @kwic.define_singleton_method(:abridge_note) { |s| s }

    args = { work: 'T0001', juan: 1, around: 3 }
    found = @kwic.search_near('"法鼓" NEAR/5 "迦葉"', args)

    assert_equal 1, found[:num_found], '只有 10 與 13 相距 5 以內'
    assert_equal found[:num_found], @kwic.count_near('"法鼓" NEAR/5 "迦葉"', args)
  end
end
