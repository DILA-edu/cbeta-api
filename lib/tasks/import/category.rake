namespace :import do    
  desc "匯入部類 ID"
  task :category => :environment do
    ImportCategory.new.import
  end
end

class ImportCategory
  def import
    fn = Rails.root.join('data-static', 'categories.json')
    categories = JSON.load_file(fn)

    # 包在 transaction 裡: 中途 abort / 例外時保留舊資料, 不會留下空表或只匯一半
    Category.transaction do
      Category.delete_all
      categories.each_pair do |k,v|
        Category.create(n: k.to_i, name: v)
      end
    end
  end
end
