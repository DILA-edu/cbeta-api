class JuanLine < ActiveRecord::Base
  def self.find_by_vol(vol)
    jl = JuanLine.where(vol: vol).order(:lb).first
    if jl.nil?
      raise CbetaError.new(404), "無此冊號: #{vol}"
    end
    lb = jl.lb.sub(/^0000/, '')
    return jl.work, jl.juan, lb
  end
    
  # 取得某經、某卷 的 第一個 lb 及其冊數
  def self.get_first_lb_by_work_juan(work, juan)
    jl = JuanLine.where("work=? AND juan=?", work, juan).first
    raise CbetaError.new(404), "找不到 佛典編號: #{work}, 卷號: #{juan}" if jl.nil?

    lb = jl.lb

    # LC0001 的第一頁是 a001, 
    # 為了讓它的排序在 0001 之前, JuanLine 在 lb 前加了 0000
    # 所以這裡要去掉。
    # 但是 GA0077 的第一頁又真的是 0000, 所以要先判斷 lb 的 size
    lb.delete_prefix!('0000') if lb.size > 7

    return jl.vol, lb
  end
  
  def self.get_juan_by_vol_work_lb(vol, work, lb)
    jl = JuanLine.where("vol=? AND work=? AND lb<=?", vol, work, lb).last
    return nil if jl.nil?
    return jl.juan
  end
end
