class UnicodeService
  def initialize
    @u2 = Unihan2.new
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
