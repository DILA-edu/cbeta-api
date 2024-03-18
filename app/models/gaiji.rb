class Gaiji < ActiveRecord::Base
  def self.replace_zzs_with_pua(q)
    return nil if q.nil?
    return q unless q.include? '['
    r = q.gsub(/\[[^\]]+\]/) do |s|
      g = self.find_by zzs: s
      g.nil? ? s : g.pua
    end
    r
  end
end
