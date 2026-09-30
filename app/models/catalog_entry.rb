class CatalogEntry < ActiveRecord::Base
  # 以冊號 (例: T01) 找原書目錄裡該冊的節點，找不到回傳 nil。
  # 原書目錄各藏的第一層節點是 orig-T、orig-X 等 (見 import:catalog 的 serial_no)。
  def self.find_by_vol(vol)
    return nil unless vol =~ /^(#{CBETA::CANON})\d{2,3}$/

    where(parent: "orig-#{$1}").where('label LIKE ?', "#{vol}%").order(:sort).first
  end
end
