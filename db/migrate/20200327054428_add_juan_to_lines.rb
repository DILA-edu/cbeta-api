class AddJuanToLines < ActiveRecord::Migration[6.0]
  def change
    add_column :lines, :juan, :integer
  end
end
