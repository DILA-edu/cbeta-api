class AddIndexToXmlfiles < ActiveRecord::Migration[6.0]
  def change
    add_index :xml_files, [:work, :vol]
  end
end
