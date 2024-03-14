class UnicodeService
  def initialize
    @u2 = Unihan2.new
  end

  def gaiji_unicode(g, normalize: True)
    u = g['unicode']
    unless u.blank?
      return u if level2?(u)
    end

    return nil unless normalize

    r = g['norm_unicode']
    return r if level2?(r)

    r = g['norm_big5_char']
    return r unless r.blank?

    nil
  end

  def level1?(code)
    return false if code.nil?
    # Unicode 3.0 以內 在 mobile 可以正確顯示
    v = @u2.ver(code)
    raise CbetaError.new(500), "Unihan2.ver 回傳 nil, code: #{code}" if v.nil?
    v <= 3
  end

  def level2?(code)
    return false if code.nil?
    # Unicode 10 以內 在 desktop 有字型可以顯示
    @u2.ver(code) <= 10
  end
end
