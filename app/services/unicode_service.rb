class UnicodeService
  # 超出 Unicode 3.0 但仍直接採用的字元 (2026-11-02 CBETA 指示)
  LEVEL1_EXTRA_CHARS = /[ȧ⏑⏓㉑-㉟㊱-㊿]/

  def initialize
    @u2 = Unihan2.new
  end

  # 決定是否採用 unicode 字元 或 unicode 通用字
  def gaiji_unicode(g, normalize: true)
    u = g['uni_char']
    return u unless u.blank?

    return nil unless normalize

    r = g['norm_uni_char']
    return r unless r.blank?

    r = g['norm_big5_char']
    return r unless r.blank?

    nil
  end

  def level1?(code)
    return false if code.nil?
    return true if LEVEL1_EXTRA_CHARS.match?(to_char(code))

    # Unicode 3.0 以內 在 mobile 可以正確顯示
    v = @u2.ver(code)
    raise CbetaError.new(500), "Unihan2.ver 回傳 nil, code: #{code}" if v.nil?
    v <= 3
  end

  def level2?(code)
    return false if code.nil?
    # Unicode 10 以內 在 desktop 有字型可以顯示 (預設可能沒有，需要安裝字型)
    @u2.ver(code) <= 10
  end

  private

  # code 可以是字元、hex codepoint 字串 (例 "3251") 或 Integer, 與 Unihan2#ver 相同
  def to_char(code)
    return code.chr(Encoding::UTF_8) if code.is_a?(Integer)
    return code if code.size == 1

    code.hex.chr(Encoding::UTF_8)
  end
end
