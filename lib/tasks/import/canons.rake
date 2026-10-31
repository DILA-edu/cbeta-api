namespace :import do  
  task :canons => :environment do
    importer = ImportCanons.new
    importer.import
  end
end

class ImportCanons  
  def initialize
    @canon_uuid = read_uuid
  end
  
  def import
    fn = File.join(Rails.application.config.cbeta_data, 'canons.yml')
    canons = YAML.load_file(fn)
    # 包在 transaction 裡: 中途 abort / 例外時保留舊資料, 不會留下空表或只匯一半
    Canon.transaction do
      Canon.delete_all
      canons.each do |id, v|
        uuid = @canon_uuid[id]
        Canon.find_or_create_by(id2: id, uuid: uuid) do |c|
          c.name = v['short']
        end
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
