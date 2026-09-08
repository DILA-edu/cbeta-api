require 'test_helper'

# 鎖住 API 對外承諾的查詢語法解析結果 (見 static_pages/search_extended.haml)。
class CbetaSearch::QueryParserTest < ActiveSupport::TestCase
  setup do
    @parser = CbetaSearch::QueryParser.new
  end

  test '不含雙引號的查詢是單一詞組, 半形空格要保留' do
    q = @parser.parse('Pāli Text Society')

    assert_equal :phrase, q.type
    assert_equal 'pāli text society', q.phrase
  end

  test '單一詞組加不加雙引號結果相同' do
    assert_equal @parser.parse('法鼓').phrase, @parser.parse('"法鼓"').phrase
    assert_equal :phrase, @parser.parse('"法鼓"').type
  end

  test 'AND: 空格分隔的多個詞組' do
    q = @parser.parse('"法鼓" "聖嚴"')

    assert_equal :bool, q.type
    assert_equal %w[法鼓 聖嚴], q.must
    assert_empty q.should_groups
    assert_empty q.must_not
  end

  test 'OR: 以 | 分隔' do
    q = @parser.parse('"波羅蜜" | "波羅密"')

    assert_equal :bool, q.type
    assert_empty q.must
    assert_equal [%w[波羅蜜 波羅密]], q.should_groups
  end

  test 'NOT: 以 ! 開頭' do
    q = @parser.parse('"迦葉" !"迦葉佛"')

    assert_equal :bool, q.type
    assert_equal %w[迦葉], q.must
    assert_equal %w[迦葉佛], q.must_not
  end

  test 'OR 的優先權高於空白隱含的 AND' do
    q = @parser.parse('"法鼓" "迦葉" | "阿難" !"迦葉佛"')

    assert_equal %w[法鼓], q.must
    assert_equal [%w[迦葉 阿難]], q.should_groups
    assert_equal %w[迦葉佛], q.must_not
  end

  test 'NEAR: 兩個詞' do
    q = @parser.parse('"法鼓" NEAR/7 "迦葉"')

    assert_equal :near, q.type
    assert_equal %w[法鼓 迦葉], q.near_terms
    assert_equal [7], q.near_distances
  end

  test 'NEAR: 多個詞' do
    q = @parser.parse('"老子" NEAR/7 "道" NEAR/3 "經"')

    assert_equal :near, q.type
    assert_equal %w[老子 道 經], q.near_terms
    assert_equal [7, 3], q.near_distances
  end

  test 'Exclude: 排除後搭配' do
    q = @parser.parse('"舍利" -"舍利弗"')

    assert_equal :exclude, q.type
    assert_equal '舍利', q.phrase
    assert_equal '弗', q.exclude_suffix
    assert_nil q.exclude_prefix
  end

  test 'Exclude: 排除前搭配' do
    q = @parser.parse('"直心" -"正直心"')

    assert_equal :exclude, q.type
    assert_equal '直心', q.phrase
    assert_equal '正', q.exclude_prefix
    assert_nil q.exclude_suffix
  end

  test 'Exclude: 被排除的字串必須包含原查詢詞' do
    error = assert_raises(CbetaError) { @parser.parse('"舍利" -"迦葉"') }
    assert_equal 400, error.code
  end

  test 'escape: 查詢詞中的雙引號、單引號、半形減號' do
    q = @parser.parse('"Your" "\\"mang\\-kun\\""')

    assert_equal :bool, q.type
    assert_equal ['your', '"mang-kun"'], q.must
  end

  test 'escape 的單引號不會被當成語法符號' do
    q = @parser.parse("samantato \\'nantanāvāptiśāsani")

    assert_equal :phrase, q.type
    assert_equal "samantato 'nantanāvāptiśāsani", q.phrase
  end

  test '不支援的語法回 400' do
    ['("A" | "B") "C"', '"A" ~5 "B"', '"A" & "B"'].each do |q|
      error = assert_raises(CbetaError) { @parser.parse(q) }
      assert_equal 400, error.code, "應拒絕: #{q}"
    end
  end

  test '空查詢回 400' do
    [nil, '', '   '].each do |q|
      error = assert_raises(CbetaError) { @parser.parse(q) }
      assert_equal 400, error.code
    end
  end

  test 'NEAR 不能與其他運算子混用' do
    error = assert_raises(CbetaError) { @parser.parse('"A" NEAR/3 "B" !"C"') }
    assert_equal 400, error.code
  end

  test '只有排除條件的查詢回 400' do
    error = assert_raises(CbetaError) { @parser.parse('!"迦葉佛"') }
    assert_equal 400, error.code
  end
end
