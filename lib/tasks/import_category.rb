class ImportCategory
  def initialize
    @folder = File.join(Rails.application.config.cbeta_data, 'category')
  end  
  
  def import
    import_categories
    import_orig_categories
    
    fn = File.join(@folder, 'work_categories.json')
    s = File.read(fn)
    works = JSON.parse(s)
    
    works.each_pair do |k,v|
      if k.include? '..'
        w1, w2 = k.split('..')
        Work.where(n: w1..w2).sort.each do |w|
          update(w, v)
        end        
      else
        update(k, v)
      end
    end
  end
  
  private
  
  def import_categories
    Category.delete_all
    
    fn = File.join(@folder, 'categories.json')
    s = File.read(fn)
    categories = JSON.parse(s)
    
    categories.each_pair do |k,v|
      Category.create(n: k.to_i, name: v)
    end
  end

  def import_orig_categories
    folder = File.join(Rails.application.config.cbeta_data, 'orig-category')
    Dir["#{folder}/*.json"].each do |f|
      works = JSON.parse(File.read(f))
      works.each_pair do |k, v|
        work = Work.find_by(n: k)
        if work.nil?
          if k.start_with?('T')
            next
          else
            abort "Work 找不到 #{k}"
          end
        end
        work.update(orig_category: v)
      end
    end
  end

  def update(work, data)
    if work.is_a?(String)
      w = Work.find_by n: work
    else
      w = work
    end
    return if w.nil?
    
    w.category     = data['category_names']
    w.category_ids = data['category_ids']
    w.save
  end
  
end