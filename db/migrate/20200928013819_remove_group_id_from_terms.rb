class RemoveGroupIdFromTerms < ActiveRecord::Migration[6.0]
  def change
    remove_column :terms, :group_id, :integer
  end
end
