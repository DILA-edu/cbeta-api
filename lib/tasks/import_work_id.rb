require 'csv'
class ImportWorkId
  def initialize
  end
  
  def import(canon)
    folder = Rails.application.config.cbeta_data
    if canon.nil?
      Dir["#{folder}/work-id/*.csv"].sort.each do |f|
        @canon = File.basename(f, '.csv')
        import_file f
      end
    else
      fn = File.join(folder, 'work-id', "#{canon}.csv")
      import_file(fn)
    end
  end
  
  private
  
  def import_file(fn)
    $stderr.puts "import work_id #{fn}"
    CSV.foreach(fn, headers: true) do |row|
      if row['work'].match(/^(.*)\.\.(.*)$/)
        Range.new($1, $2).each do |w|
          update_work(w, row['vol'], row['type'])
        end
      else
        update_work(row['work'], row['vol'], row['type'])
      end
    end
  end

  def update_work(work, vol, type)
    w = Work.find_or_create_by(n: work)
    w.update(canon: @canon, vol: vol)

    if type.blank?
      w.update(work_type: 'textbody') # 預設：正文
    else
      w.update(work_type: type) # non-textbody 表示 非正文
    end
  end
  
end