# 卷跨冊時 (例: L1557 卷 17 由 L130 接到 L131) 一卷記成多段, 一段一列。
# seq 從 1 起算; uuid / content_uuid 只放在 seq = 1 那列, 續段為 NULL。
class AddSeqToJuanLines < ActiveRecord::Migration[8.1]
  def change
    add_column :juan_lines, :seq, :integer, null: false, default: 1
    remove_index :juan_lines, %i[work juan], name: 'index_juan_lines_on_work_and_juan'
    add_index :juan_lines, %i[work juan seq], unique: true
  end
end
