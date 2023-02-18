class AddSortToCatalogEntries < ActiveRecord::Migration[6.0]
  def change
    add_column :catalog_entries, :sort, :integer
    add_index  :catalog_entries, [:parent, :sort]
  end
end
