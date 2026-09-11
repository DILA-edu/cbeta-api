require 'test_helper'

# search/similar 的第二階段。Matrix 改成攤平的 Array、traceback 改成延後執行，
# 這些都是效能改寫，對外的 score 與 highlight 必須一字不差。
class SmithWatermanTest < ActiveSupport::TestCase
  # 改寫前的實際輸出，逐字鎖住。
  GOLDEN = [
    {
      q: '諸行無常是生滅法',
      text: '爾時世尊告諸比丘諸行無常是生滅法生滅滅已寂滅為樂如是我聞',
      score: 16,
      highlight: '爾時世尊告<em>諸</em>比丘<mark>諸行無常是生滅法</mark><em>生</em><em>滅</em>' \
                 '<em>滅</em>已寂<em>滅</em>為樂如<em>是</em>我聞'
    },
    {
      q: '一切有為法如夢幻泡影',
      text: '一切有為法如夢幻泡影如露亦如電應作如是觀',
      score: 20,
      highlight: '<mark>一切有為法如夢幻泡影</mark><em>如</em>露亦<em>如</em>電應作<em>如</em>是觀'
    },
    {
      q: '一切有為法如夢幻泡影',
      text: '佛告須菩提一切有為法應觀如是夢幻之影',
      score: 14,
      highlight: '佛告須菩提<mark>一切有為法</mark><del>應</del><del>觀</del><mark>如</mark>' \
                 '<del>是</del><mark>夢幻<del>之</del>影</mark>'
    },
    {
      q: '諸惡莫作眾善奉行',
      text: '七佛通誡偈曰諸惡莫作眾善奉行自淨其意是諸佛教',
      score: 16,
      highlight: '七佛通誡偈曰<mark>諸惡莫作眾善奉行</mark>自淨其意是<em>諸</em>佛教'
    },
    {
      q: '菩薩清涼月',
      text: '完全無關的文字內容此處沒有共同字',
      score: 0,
      highlight: '完全無關的文字內容此處沒有共同字完全無關的文字內容此處沒有共同字'
    },
    {
      q: '阿耨多羅三藐三菩提',
      text: '得阿耨多羅三藐三菩提心者應如是住',
      score: 18,
      highlight: '得<mark>阿耨多羅三藐三菩提</mark>心者應如是住'
    }
  ].freeze

  test 'score 與 highlight 與改寫前逐字相同' do
    GOLDEN.each do |c|
      sw = SmithWaterman.new(c[:q], c[:text])
      sw.align!

      assert_equal c[:score], sw.score, "score 不同: #{c[:q]}"
      assert_equal c[:highlight], sw.alignment_inspect_b, "highlight 不同: #{c[:q]}"
    end
  end

  test 'score! 不做 traceback, alignment 第一次被取用時才算' do
    sw = SmithWaterman.new(GOLDEN[0][:q], GOLDEN[0][:text])

    assert_equal GOLDEN[0][:score], sw.score!
    assert_nil sw.instance_variable_get(:@alignment)

    sw.alignment
    assert_not_nil sw.instance_variable_get(:@alignment)
  end

  test 'score! 重複呼叫不會重算, 也不會改變結果' do
    sw = SmithWaterman.new(GOLDEN[1][:q], GOLDEN[1][:text])

    assert_equal sw.score!, sw.score!
    assert_equal GOLDEN[1][:highlight], sw.alignment_inspect_b
  end

  test 'align! 仍回傳 alignment' do
    sw = SmithWaterman.new(GOLDEN[0][:q], GOLDEN[0][:text])

    assert_kind_of Array, sw.align!
    assert_equal sw.alignment, sw.align!
  end

  test 'max_score 是真正的上界: 不小於實際算出來的分數' do
    GOLDEN.each do |c|
      sw = SmithWaterman.new(c[:q], c[:text])
      sw.score!

      assert_operator SmithWaterman.max_score(c[:q], c[:text]), :>=, sw.score,
                      "上界低於實際分數: #{c[:q]}"
    end
  end

  test 'max_score 算的是 multiset 交集, 重複字元只能配對一次' do
    # b 只有一個「法」，不能跟 a 的兩個「法」各配一次
    assert_equal 2, SmithWaterman.max_score('法法', '法')
    assert_equal 4, SmithWaterman.max_score('法法', '法法')
    assert_equal 0, SmithWaterman.max_score('菩薩', '無關')
  end

  test 'max_score 用呼叫端指定的 gain' do
    assert_equal 6, SmithWaterman.max_score('法鼓山', '法鼓山', gain: 2)
    assert_equal 15, SmithWaterman.max_score('法鼓山', '法鼓山', gain: 5)
    assert_equal 0, SmithWaterman.max_score('法鼓山', '法鼓山', gain: 0)
  end

  test 'gain / penalty 可覆寫, 上界跟著 gain 走' do
    q = '諸行無常'
    text = '諸行無常是生滅法'

    sw = SmithWaterman.new(q, text, gain: 5, penalty: -2)
    sw.score!

    assert_equal 20, sw.score
    assert_operator SmithWaterman.max_score(q, text, gain: 5), :>=, sw.score
  end

  test 'penalty 為正數要拋錯' do
    assert_raises(RuntimeError) { SmithWaterman.new('法', '法', penalty: 1) }
  end
end
