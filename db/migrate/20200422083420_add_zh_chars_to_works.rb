class AddZhCharsToWorks < ActiveRecord::Migration[6.0]
  def change
    add_column :works, :zh_chars, :integer
    add_column :works, :en_words, :integer
  end
end
