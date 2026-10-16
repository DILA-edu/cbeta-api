# 目次節點的完整路徑 (例: 後集一門/諸經引證節略/阿含經)，由 import:toc 走訪時算好。
# 原本 search/toc 每筆結果都沿 parent 逐層查詢組出，而且 toc_nodes.n 不唯一
# (例: B0002 兩組目次共用編號)，以 n 反查可能接到另一組目次的祖先。
class AddLabelPathToTocNodes < ActiveRecord::Migration[8.1]
  def change
    add_column :toc_nodes, :label_path, :text
  end
end
