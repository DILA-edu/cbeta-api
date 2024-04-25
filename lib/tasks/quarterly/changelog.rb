class Changelog
  def self.get_ignore_list(config)
    fn = File.join(config[:change_log], "#{config[:q2]}.yml")
    unless File.exist?(fn)
      puts "忽略清單不存在: #{fn}".red
      return { 'ignore_all' => [], 'ignore_puncs' => [] }
    end

    r = YAML.load_file(fn)
    r['ignore_all']   ||= []
    r['ignore_puncs'] ||= []
    r
  end
end
