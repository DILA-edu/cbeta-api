class ChangeIndexId2ToPerson < ActiveRecord::Migration[8.0]
  def change
    remove_index :people, column: :id2

    # 設定欄位不能為 NULL
    change_column_null :people, :id2, false

    add_index :people, :id2, unique: true
  end
end
