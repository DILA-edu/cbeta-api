class CreateChanges < ActiveRecord::Migration[8.0]
  def change
    create_table :changes do |t|
      t.string :lb, null: false
      t.string :html, null: false
      t.string :ver, null: false

      t.index [:lb, :ver], unique: true

      t.timestamps
    end
  end
end
