require 'test_helper'

class UnicodeServiceTest < ActiveSupport::TestCase
  setup do
    @service = UnicodeService.allocate # gaiji_unicode 用不到 Unihan2
  end

  test 'gaiji_unicode 預設採用通用字' do
    g = { 'uni_char' => '', 'norm_uni_char' => '甲' }

    assert_equal '甲', @service.gaiji_unicode(g)
    assert_nil @service.gaiji_unicode(g, normalize: false)
  end

  test 'gaiji_unicode 有 unicode 字元時直接採用' do
    assert_equal '乙', @service.gaiji_unicode({ 'uni_char' => '乙', 'norm_uni_char' => '甲' })
  end
end
