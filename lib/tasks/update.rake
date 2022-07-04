require 'pp'
include ActionView::Helpers::NumberHelper

namespace :update do
  
  desc "更新經號排序"
  task :sort_order => :environment do
    @work_sort_order = {}
    Work.find_each.with_index do |w, i|
      if (i % 1000) == 0
        $stderr.puts "update work.sort_order #{number_with_delimiter(i)}"
      end
      w.sort_order = sort_order(w.n) + w.n
      w.save
    end
    
    TocNode.find_each.with_index do |row, i|
      if (i % 1000) == 0
        $stderr.puts "update toc_node.sort_order #{number_with_delimiter(i)}"
      end
      row.sort_order = sort_order(row.work) + row.work
      row.save
    end
  end
  
  # @param n [String] 佛典編號
  # @return [String] 排序用編號
  def sort_order(n)
    return @work_sort_order[n] if @work_sort_order.key? n
    
    canon = CBETA.get_canon_id_from_work_id(n)
    r = CBETA.get_sort_order_from_canon_id(canon)
    
    @work_sort_order[n] = r
    r
  end
end