require 'pp'

class ImportPlace
  def initialize
    @folder = Rails.root.join('data')
  end
  
  def import
    # data/places.json 來自 /Users/ray/Documents/Projects/CBETA/place
    fn = File.join(@folder, 'places.json')
    s = File.read(fn)
    works = JSON.parse(s)
    works.each do |k,v|
      w = Work.find_by n: k
      next if w.nil?
      w.update v
    end
  end
  
end