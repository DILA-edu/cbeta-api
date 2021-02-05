class AddTypeToWorks < ActiveRecord::Migration[6.0]
  def change
    add_column :works, :work_type, :string
  end
end
