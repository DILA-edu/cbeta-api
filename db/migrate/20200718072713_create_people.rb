class CreatePeople < ActiveRecord::Migration[6.0]
  def change
    create_table :people do |t|
      t.string :id2
      t.string :name
      t.index :id2
      t.index :name
    end
  end
end
