class AddLbEndToJuanlines < ActiveRecord::Migration[6.0]
  def change
    add_column :juan_lines, :lb_end, :string
  end
end
