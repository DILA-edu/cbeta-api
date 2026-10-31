class IntToZht
  NUMS = %w[零 一 二 三 四 五 六 七 八 九]
  UNITS = %w[十 百 千]

  # 0 ~ 9999。例: 10 → 十, 110 → 一百一十, 1010 → 一千零一十
  def self.convert(num)
    return NUMS[0] if num == 0

    digits = num.to_s.chars.map(&:to_i)
    result = +''
    zero = false # 前面有還沒輸出的 0

    digits.each_with_index do |digit, index|
      position = digits.size - index - 1

      if digit == 0
        zero = true
        next
      end

      result << NUMS[0] if zero
      zero = false
      result << NUMS[digit]
      result << UNITS[position - 1] if position > 0
    end

    # 只有開頭的「一十」省略為「十」(十一), 中間的要保留 (一百一十)
    result.sub(/\A一十/, '十')
  end
end
