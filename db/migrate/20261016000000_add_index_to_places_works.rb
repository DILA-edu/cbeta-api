# Work#to_hash 每次都查 places 關聯, 原本 places_works 沒有任何 index (每次 full scan)。
# 不設 unique: import:work_info 目前不保證不重複, 加 unique 可能讓匯入失敗。
class AddIndexToPlacesWorks < ActiveRecord::Migration[8.1]
  def change
    add_index :places_works, [ :work_id, :place_id ]
  end
end
