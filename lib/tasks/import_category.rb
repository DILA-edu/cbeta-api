class ImportCategory
  def import
    Category.delete_all
    fn = Rails.root.join('data-static', 'categories.json')
    categories = JSON.load_file(fn)
    
    categories.each_pair do |k,v|
      Category.create(n: k.to_i, name: v)
    end
  end
end
