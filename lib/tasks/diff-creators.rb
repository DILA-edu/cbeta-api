# 停用，完全按照 authority 的資料
require 'net/http'
class DiffCreators
  def self.diff
    jap = ('T2185'..'T2731')
    authority = read_creators_from_authority
    metadata = read_creators_from_metadata
    error = ''
    count = 0
    authority.keys.sort.each do |k|
      a = Set.new(authority[k]['creators_with_id'].split(';'))
      unless metadata.key? k
        unless (k >= 'T2185') and (k <= 'T2731') # 日本著作
          count += 1
          error += <<~MSG
          ----------
          經號: #{k}
          authority: #{a}
          metadata: 缺
          MSG
        end
        next
      end
      b = metadata[k]['creators_with_id']
      b = Set.new(b.split(';')) unless b.nil?
      if not a == b
        count += 1
        error += <<~MSG
        ----------
        作譯者不符: #{k}
        authority: #{a.to_a.join(';')}
        metadata: #{b.to_a.join(';')}
        MSG
      end
    end
    if error.empty?
      puts "無差異"
    else
      fn = Rails.root.join('log/diff-creators.log')
      File.write(fn, error)
      puts "發現 #{count} 筆差異，請查看 #{fn}".red
    end
  end
  
  def self.read_creators_from_authority
    $stderr.puts "read creators from authority"
    url = 'http://authority-dev.dila.edu.tw/catalog/tools/t.php'
    uri = URI(url)
    response = Net::HTTP.get(uri)
    
    begin
      JSON.parse(response)
    rescue
      puts "DILA Authority 回傳錯誤"
      puts url
      abort "diff-creators.rb 行號: #{__LINE__}"
    end
  end

  def self.read_creators_from_metadata
    $stderr.puts "read creators from metadata"
    base = Rails.application.config.cbeta_data
    fn = File.join(base, 'creators', 'creators-by-canon', 'T.json')
    begin
      JSON.load(File.open(fn))
    rescue
      puts "Error: diff-creators.rb 行號 #{__LINE__}"
      puts "Parse JSON File error: #{fn}"
      exit
    end
  end
end