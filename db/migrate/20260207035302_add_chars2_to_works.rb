class AddChars2ToWorks < ActiveRecord::Migration[8.1]
  def change
    add_column :works, :chars2, :integer
  end
end
