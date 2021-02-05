require 'json'

class ImportAlt
  def initialize
    @data_folder = Rails.application.config.cbeta_data
  end
  
  def import
    import_from_alt
  end
  
  private
    
  def import_from_alt
    folder = File.join(@data_folder, 'alternates')
    Dir["#{folder}/*.json"].each do |fn|
      $stderr.puts "import_alt from #{fn}"
      alts = File.open(fn) { |f| JSON.load(f) }
      alts.each_pair do |k,v|
        # 例 B0130 因為 CBETA 也有選錄部份為 B23n0130, 所以不把 B0130 當做 alt
        next if v['alt'].include? '選錄'
        
        w = Work.find_by n: k
        w.update(v) unless w.nil?
      end
    end
  end
  
end