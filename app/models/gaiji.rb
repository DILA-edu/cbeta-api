class Gaiji < ActiveRecord::Base
  def self.replace_pua_with_zzs(text)
    text.gsub(/[\u{F0000}-\u{FFFFF}]/) do
      pua = $&
      g = self.find_by(pua: pua)
      g.nil? ? pua : g.zzs
    end
  end

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
