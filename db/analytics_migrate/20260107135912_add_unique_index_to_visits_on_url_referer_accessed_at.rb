class AddUniqueIndexToVisitsOnUrlRefererAccessedAt < ActiveRecord::Migration[8.0]
  def change
    remove_index :visits, name: "index_visits_on_url_and_referer_and_accessed_at"
    add_index :visits, [:url, :referer, :accessed_at], unique: true,
              name: "index_visits_on_url_and_referer_and_accessed_at"
  end
end
