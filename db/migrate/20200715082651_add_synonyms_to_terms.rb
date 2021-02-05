class AddSynonymsToTerms < ActiveRecord::Migration[6.0]
  def change
    add_column :terms, :synonyms, :text
  end
end
