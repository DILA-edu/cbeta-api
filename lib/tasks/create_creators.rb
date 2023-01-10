class CreateCreatorsList

  def initialize
    read_person_authority
    @unihan = Unihan2.new
    @strokes = {}
    @unknown = []

    fn = Rails.root.join('log', 'create_creators.log')
    @log = File.open(fn, 'w')
  end
  
  def create
    result = read_contributors

    folder = Rails.root.join('data')
    FileUtils.makedirs(folder)

    fn = File.join(folder, 'all-creators.json')
    $stderr.puts "write #{fn}"
    s = JSON.pretty_generate(@all_creators)
    File.write(fn, s)

    fn = File.join(folder, 'all-creators-with-alias.json')
    $stderr.puts "write #{fn}"
    s = JSON.pretty_generate(@all_creators_with_alias)
    File.write(fn, s)

    fn1 = File.join(folder, 'creators-by-strokes-with-works.json')
    fn2 = File.join(folder, 'creators-by-strokes.json')
    output_by_strokes(fn1, fn2)
  end
  
  private

  def handle_preson(person)
    id = person['id']
    aliases_all = Set.new
    aliases_byline = Set.new
    regular = nil
    person.xpath('persName').each do |e|
      s = e.content
      if not e.key?('type')
        regular = s if e['lang'] == 'zho-Hant'
      elsif e['type'] == 'alternative'
        aliases_all << s
        works = Work.where("byline LIKE ?", "%#{s}%")
        aliases_byline << s unless works.empty?
      end
    end
    @person_names[id] = { regular_name: regular }
    unless aliases_all.empty?
      @person_names[id][:aliases_all] = aliases_all.to_a
    end
    unless aliases_byline.empty?
      @person_names[id][:aliases_byline] = aliases_byline.to_a
    end
  end

  def output_by_strokes(dest1, dest2)
    r = [
      { 
        title: '選擇全部', children: []
      }
    ]
    all_strokes = @strokes.to_a.sort
    
    all_strokes.each do |stroke_a|
      stroke = stroke_a[0]
      chars_h = stroke_a[1]
      
      stroke_children = []
      r.first[:children] << {
        title: "#{stroke}劃(stroke)",
        children: stroke_children
      }
      
      chars_h.each_pair do |char, creators_h|
        char_children = []
        stroke_children << {
          title: char,
          children: char_children
        }
        creators_h.each_pair do |creator_key, creator_h|
          char_children << {
            key: creator_key,
            title: creator_h[:title],
            children: creator_h[:children]
          }
        end
      end    
    end
    
    r.first[:children] << {
      title: "缺作譯者 ID",
      children: @unknown
    }
    
    s = JSON.pretty_generate(r)
    puts "write #{dest1}"
    File.write(dest1, s)
    
    r.first[:children].pop
    
    r.first[:children].each do |stroke|
      stroke[:children].each do |char|
        char[:children].each do |creator|
          creator.delete(:children)
        end
      end
    end
    
    s = JSON.pretty_generate(r)
    puts "write #{dest2}"
    File.write(dest2, s)
  end  

  def read_contributors
    @all_creators = {}
    @all_creators_with_alias = {}

    folder = Rails.configuration.x.work_info
    Dir["#{folder}/*.json"].each do |f|
      $stderr.puts "read #{f}"
      works = JSON.parse(File.read(f))

      works.each do |work_id, work|
        next unless work.key?('contributors')
        @log.puts "read_contributors, work_id: #{work_id}"
        long_title = "#{work_id} %s" % work['title']
        if work.key?('juans')
          long_title << " (%d卷)" % work['juans']
        else
          puts "#{work_id} 沒有 juans".red
        end
        long_title << "【#{work['byline']}】" if work.key?('byline')

        unless work.key?('contributors')
          @unknown << {
            key: work_id,
            title: long_title
          }
          next
        end
    
        work['contributors'].each do |h|
          next unless h.key?('id')
          id = h['id']
          unless @all_creators.key?(id)
            @all_creators[id] = h['name']
          end
          
          if @person_names.key?(id)
            unless @all_creators_with_alias.key?(id)
              @all_creators_with_alias[id] = @person_names[id]
            end
          else
            $stderr.puts "#{__LINE__} Authority 裡沒有 #{id}".red
          end      
          record_by_stroke(id, h['name'], work_id, long_title)
        end
      end
    end

    # 按 id 排序
    @all_creators = @all_creators.to_a.sort
    @all_creators_with_alias = @all_creators_with_alias.sort.to_h
  end
  
  def read_person_authority
    @person_names = {}
    fn = File.join(
      Rails.configuration.x.authority, 
      'authority_person', 
      'Buddhist_Studies_Person_Authority.xml'
    )
    $stderr.puts "read #{fn}"
    doc = File.open(fn) { |f| Nokogiri::XML(f) }
    doc.remove_namespaces!
    i = 0
    doc.xpath('//person').each do |person|
      handle_preson(person)
      i += 1
      print number_with_delimiter(i) + ' ' if (i % 500) == 0
    end
  end

  def record_by_stroke(creator_key, name, work_id, long_title)
    char = name[0]
    stroke = @unihan.strokes(char)
    @strokes[stroke]={} unless @strokes.key? stroke
    
    h = @strokes[stroke]
    h[char]={} unless h.key? char
    
    h = @strokes[stroke][char]
    unless h.key? creator_key
      h[creator_key] = { 
        title: name,
        children: []
      }
    end
    
    a = @strokes[stroke][char][creator_key][:children]
    a << {
      key: work_id,
      title: long_title
    }
    @log.puts "stroke: #{stroke}, char: #{char}, creator_key: #{creator_key}, work_id: #{work_id}"
  end  

end
