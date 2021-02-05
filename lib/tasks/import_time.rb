class ImportTime
  def initialize
    @folder = File.join(Rails.application.config.cbeta_data, 'time', 'year-by-canon')
  end
  
  def import
    @dynasties = Set.new
    Dir["#{@folder}/*.json"].each do |f|
      import_canon(f)
    end
    
    fn = Rails.root.join('log', 'dynasty-all.txt')
    s = @dynasties.to_a.join("\n")
    File.write(fn, s)
  end
  
  private
  
  def import_canon(fn)
    s = File.read(fn)
    works = JSON.parse(s)
    works.each_pair do |k,v|
      @dynasties << v['dynasty']
      
      w = Work.find_by n: k
      next if w.nil?
      
      if v.key?('dynasty')
        w.time_dynasty = v['dynasty']
      else
        w.time_dynasty = 'unknown'
      end

      w.time_from    = v['time_from']
      w.time_to      = v['time_to']
      w.save
    end
  end
end