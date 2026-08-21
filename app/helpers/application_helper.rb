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

  # 側邊欄在 API 與網頁兩種 controller 底下都會 render,但只有
  # WebController 有 current_user helper。這裡直接讀 session,
  # 讓 sidebar 不必知道自己在哪一種 controller 下。
  def signed_in_user
    return @signed_in_user if defined?(@signed_in_user)

    @signed_in_user = session[:user_id] && User.find_by(id: session[:user_id])
  end
end
