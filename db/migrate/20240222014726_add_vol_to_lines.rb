class AddVolToLines < ActiveRecord::Migration[6.1]
  def change
    change_table :lines do |t|
      t.string :work, :vol, :page, :col, :line
      t.integer :ser_no
      t.index :ser_no
      t.index [:vol, :page, :col, :line]
      t.index [:work, :juan, :ser_no]
    end
  end
end
