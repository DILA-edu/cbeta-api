class CreateVisits < ActiveRecord::Migration[6.0]
  def change
    create_table :visits do |t|
      t.string :url
      t.date :accessed_at
      t.integer :count
      t.index [:url, :accessed_at]
    end
  end
end
