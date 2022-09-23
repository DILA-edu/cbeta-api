class AddRefererToVisits < ActiveRecord::Migration[6.0]
  def change
    add_column :visits, :referer, :string
    add_index  :visits, [:url, :referer, :accessed_at]
  end
end
