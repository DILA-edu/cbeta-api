class IntToZht
  NUMS = %w[零 一 二 三 四 五 六 七 八 九]
  UNITS = %w[十 百 千]

  def self.convert(num)
    return NUMS[0] if num == 0
  
    str = num.to_s
    length = str.length
    result = ""
  
    str.chars.each_with_index do |char, index|
      digit = char.to_i
      position = length - index - 1
      
      if digit != 0
        result += NUMS[digit]
        result += UNITS[position - 1] if position > 0
      elsif position == 1 && result[-1] != NUMS[0]
        result += NUMS[0]
      end
    end
  
    result.gsub(/一十/, '十').gsub(/零+$/, '')
  end
end
