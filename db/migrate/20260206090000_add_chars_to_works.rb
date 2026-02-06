class AddCharsToWorks < ActiveRecord::Migration[8.0]
  def change
    add_column :works, :chars, :integer
  end
end
