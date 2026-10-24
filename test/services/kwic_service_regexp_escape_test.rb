require 'test_helper'

# q 由使用者輸入，其中的 regex 特殊字元必須當成一般字元比對
class KwicServiceRegexpEscapeTest < ActiveSupport::TestCase
  test 'sort_word_count 將 q 中的 regex 特殊字元視為一般字元' do
    kwic = KwicService.new(Dir.mktmpdir, false)
    kwic.instance_variable_set(:@option, { word_count: 1 })
    kwic.define_singleton_method(:open_files) { |_path| true }
    kwic.define_singleton_method(:sa) { |_i| 5 }
    kwic.define_singleton_method(:read_str) { |_offset, _length| +'甲乙丙丁戊般+若己庚' }

    kwic.send(:sort_word_count, '般+若', [ [ 'T/T01', 0, 1 ] ])

    assert_equal [ [ '戊', 1 ] ], kwic.instance_variable_get(:@prev_word_count)
    assert_equal [ [ '己', 1 ] ], kwic.instance_variable_get(:@next_word_count)
  end
end
