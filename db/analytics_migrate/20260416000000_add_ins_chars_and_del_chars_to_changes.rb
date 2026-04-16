class AddInsCharsAndDelCharsToChanges < ActiveRecord::Migration[8.1]
  def change
    add_column :changes, :ins_chars, :integer
    add_column :changes, :del_chars, :integer
  end
end
