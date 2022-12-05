class CreatePlaces < ActiveRecord::Migration[6.0]
  def change
    def change
      remove_column :works, :place_name, :string
      remove_column :works, :place_id,   :string
      remove_column :works, :place_long, :float
      remove_column :works, :place_lat,  :float
    end

    create_table :places do |t|
      t.string :auth_id, index: { unique: true }
      t.string :name
      t.float :longitude
      t.float :latitude
    end

    create_join_table :places, :works
  end
end
