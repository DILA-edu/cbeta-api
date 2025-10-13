class AddWorkToChanges < ActiveRecord::Migration[8.0]
  def change
    add_column :changes, :work, :string
    add_column :changes, :juan, :integer
    add_index :changes, [:work, :juan]
  end
end
