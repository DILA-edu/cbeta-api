class CreateTerms < ActiveRecord::Migration[5.2]
  def change
    create_table :terms do |t|
      t.integer :group_id
      t.string :term
    end
    add_index :terms, :group_id
    add_index :terms, :term
  end
end
