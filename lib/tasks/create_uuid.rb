class CreateUuid

  def initialize
    @dest = Rails.root.join('data-static', 'uuid')
    FileUtils.makedirs @dest
    
    @canon_names = read_canon_names
  end
  
  def create
    create_canons
    create_works
    create_juans
  end
  
  private
  
  def create_canons
    r = {}
    
    fn = File.join(@dest, 'canons.json')
    if File.exist? fn  # 如果產生過了，就讀取舊檔
      s = File.read(fn)
      r = JSON.parse(s)
    end
    
    @canon_names.each_pair do |k,v|
      next if r.key? k  # 已經產生過的，就維持舊的
      r[k] = SecureRandom.uuid
    end
    
    s = JSON.pretty_generate(r)
    
    puts "write #{fn}"
    File.write(fn, s)
  end
  
  def create_juans
    r = {}
    
    # 已經產生過的，就維持舊的
    output_filename = File.join(@dest, 'juans.json')
    if File.exist? output_filename
      s = File.read(output_filename)
      r = JSON.parse(s)
    end
    
    folder = Rails.root.join('data', 'juan-line')
    Dir.entries(folder).sort.each do |f|
      next if f.start_with? '.'
      canon_path = File.join(folder, f)
      Dir.entries(canon_path).sort.each do |f|
        next if f.start_with? '.'
        work = File.basename(f, '.json')
        path = File.join(canon_path, f)
        s = File.read(path)
        juans = JSON.parse(s)
        juans.each_pair do |k, v|
          id = "#{work}_%03d" % k.to_i
          unless r.key? id
            r[id] = {
              juan_uuid: SecureRandom.uuid,
              content_uuid: SecureRandom.uuid
            }
          end
        end
      end
    end
    
    s = JSON.pretty_generate(r)
    
    puts "write #{output_filename}"
    File.write(output_filename, s)
  end
  
  def create_works
    r = {}
    
    fn = File.join(@dest, 'works.json')
    if File.exist? fn
      s = File.read(fn)
      r = JSON.parse(s)
    end
    
    works = Work.where(alt: nil)
    works.each do |w|
      next if r.key? w.n
      r[w.n] = SecureRandom.uuid
    end
    
    s = JSON.pretty_generate(r)
    
    puts "write #{fn}"
    File.write(fn, s)
  end
  
  def read_canon_names
    fn = File.join(Rails.application.config.cbeta_data, 'canons.csv')
    r = {}
    CSV.foreach(fn, headers: true) do |row|
      r[row['id']] = row['name']
    end
    r
  end
end