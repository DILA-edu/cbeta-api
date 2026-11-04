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

  test 'level1? Unicode 3.0 以內直接採用, 以外不採用' do
    service = UnicodeService.new

    assert service.level1?('甲')
    assert service.level1?('7532')
    assert_not service.level1?('𥸩') # U+25E29, Extension B
    assert_not service.level1?('25E29')
  end

  test 'level1? 特例字元即使超出 Unicode 3.0 也直接採用' do
    service = UnicodeService.new

    %w[ȧ ⏑ ⏓ ㉑ ㉟ ㊱ ㊿].each do |c|
      assert service.level1?(c), "字元 #{c} 應採用"
      assert service.level1?(format('%X', c.ord)), "codepoint #{c} 應採用"
      assert service.level1?(c.ord), "Integer #{c} 應採用"
    end
    assert_not service.level1?('⏒') # U+23D2, 介於特例之間但不在清單內
    assert_not service.level1?('㉐') # U+3250
  end
end
