class JuanLine < ActiveRecord::Base
  def self.find_by_vol(vol)
    jl = JuanLine.where(vol: vol).order(:lb).first
    if jl.nil?
      raise CbetaError.new(404), "無此冊號: #{vol}"
    end
    lb = jl.lb.sub(/^0000/, '')
    return jl.work, jl.juan, lb
  end
  
  def self.find_by_vol_lb(vol, lb)
    # 行號有可能不是數字開頭，例如 Y01n0001_pa001a01
    # 這樣 a001 會比 0001 大，排序比較會有問題
    # 所以把 a001 改成 0000a001, 排序就會在 0001 前面
    lb2 = lb
    lb2 = "0000#{lb2}" unless lb2.match(/^\d/)
    
    jl = JuanLine.where("vol=? AND lb<=?", vol, lb2).order(:lb).last
    if jl.nil?
      msg = "無此冊數、行號, 冊號: #{vol}, 行號: #{lb2}, juan_line.rb, find_by_vol_lb"
      raise CbetaError.new(404), msg
    end

    if lb2 > jl.lb_end
      raise CbetaError.new(406), "行號 #{lb } 超出最後一行: #{jl.lb_end}"
    end

    return jl.work, jl.juan
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
