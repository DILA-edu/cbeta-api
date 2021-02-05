class ImportCanons
  
  def initialize
    @canon_uuid = read_uuid
  end
  
  def import
    Canon.delete_all
    fn = File.join(Rails.application.config.cbeta_data, 'canons.csv')
    CSV.foreach(fn, headers: true) do |row|
      id = row['id']
      uuid = @canon_uuid[id]
      Canon.find_or_create_by(id2: id, uuid: uuid) do |c|
        c.name = row['name']
      end
    end
  end
  
  private
  
  def read_uuid
    fn = Rails.root.join('data-static', 'uuid', 'canons.json')
    s = File.read(fn)
    JSON.parse(s)
  end
end