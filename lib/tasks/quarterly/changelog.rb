class Changelog
  def self.get_ignore_list(config)
    @config = config
    {
      ignore_all:   read_file('ignore-all'),
      ignore_puncs: read_file('ignore-puncs')
    }
  end

  private

  def read_file(type)
    fn = File.join(@config[:change_log], "#{config[:q2]}-#{type}.txt")
    unless File.exist?(fn)
      puts "忽略清單不存在: #{fn}".red
      return []
    end

    r = []
    File.foreach(fn) do |line|
      r << line.split.first
    end
    r
  end
end
