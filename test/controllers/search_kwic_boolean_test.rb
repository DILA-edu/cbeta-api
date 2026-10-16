require 'test_helper'

# all_in_one 的 KWIC 要和 Elasticsearch 端用同一組詞組 (QueryParser 的結果),
# 不可自己再用空白切 q 或用使用者輸入組 regex。
class SearchKwicBooleanTest < ActiveSupport::TestCase
  class FakeKwic
    attr_reader :searched, :juan_calls

    def initialize
      @searched = []
      @juan_calls = []
    end

    def search(q, _opts)
      @searched << q
      { num_found: 1, results: [ { 'vol' => 'T01', 'lb' => '0001a01', 'kwic' => q, 'work' => 'T0001', 'juan' => 1 } ] }
    end

    def search_juan(q, opts)
      @juan_calls << [ q, opts.slice(:negative_lookahead, :negative_lookbehind) ]
      { num_found: 0, results: [] }
    end
  end

  setup do
    @controller = SearchController.new
    @kwic = FakeKwic.new
  end

  test '不加引號的詞組 (含空格) 整個當一個詞查, 不拆開計數' do
    r = kwic('Pāli Text Society')

    assert_equal [ 'pāli text society' ], @kwic.searched
    assert_equal 1, r[:num_found]
  end

  test 'OR 的 | 不會被當成關鍵字' do
    kwic('"波羅蜜" | "波羅密"')
    assert_equal %w[波羅蜜 波羅密], @kwic.searched
  end

  test 'NOT 的詞組不查, AND 的詞組都查' do
    kwic('"法鼓" "聖嚴" !"法鼓山"')
    assert_equal %w[法鼓 聖嚴], @kwic.searched
  end

  test '引號內的空格保留' do
    kwic('"Pali Text"')
    assert_equal [ 'pali text' ], @kwic.searched
  end

  test 'escape 的引號還原成字元' do
    kwic('"a\"b"')
    assert_equal [ 'a"b' ], @kwic.searched
  end

  test 'Exclude 後搭配用 negative_lookahead' do
    exclude('"舍利" -"舍利弗"')
    assert_equal [ [ '舍利', { negative_lookahead: '弗' } ] ], @kwic.juan_calls
  end

  test 'Exclude 前搭配用 negative_lookbehind' do
    exclude('"菩薩" -"諸菩薩"')
    assert_equal [ [ '菩薩', { negative_lookbehind: '諸' } ] ], @kwic.juan_calls
  end

  test 'Exclude 的詞組含 regex 字元時照樣排除' do
    exclude('"a|b" -"a|bc"')
    assert_equal [ [ 'a|b', { negative_lookahead: 'c' } ] ], @kwic.juan_calls
  end

  private

  def kwic(q)
    @controller.instance_variable_set(:@q, q)
    @controller.send(:kwic_boolean, @kwic, {})
  end

  # 比照 all_in_one_sub: 先解析 (es_query 會 memoize), 再把 @q 換成主要詞組
  def exclude(q)
    @controller.instance_variable_set(:@q, q)
    query = @controller.send(:es_query)
    @controller.instance_variable_set(:@exclude, "#{query.exclude_prefix}#{query.phrase}#{query.exclude_suffix}")
    @controller.instance_variable_set(:@q, query.phrase)
    @controller.send(:kwic_boolean, @kwic, {})
  end
end
