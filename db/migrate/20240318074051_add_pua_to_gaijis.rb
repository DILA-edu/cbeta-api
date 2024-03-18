class AddPuaToGaijis < ActiveRecord::Migration[6.1]
  def change
    add_column :gaijis, :pua, :string
    add_index :gaijis, :pua
  end
end
