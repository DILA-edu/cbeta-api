module ApplicationHelper
  def debug(s)
    Rails.logger.debug s
  end
  
  # 將數字轉為加上千位號的字串
  def n2c(n)
    ActionView::Base.new.number_to_currency(n, unit: '', precision: 0)
  end

  def warn(s)
    Rails.logger.warn s
  end

end
