class WorksRenameColumnZhChars < ActiveRecord::Migration[6.0]
  def change
    rename_column :works, :zh_chars, :cjk_chars
  end
end
