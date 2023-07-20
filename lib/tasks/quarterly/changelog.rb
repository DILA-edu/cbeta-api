class Changelog
  def self.each_new_punc_work(config)
    fn = File.join(config[:change_log], "new-punc-works-#{config[:q2]}.txt")
    return unless File.exist?(fn)

    File.foreach(fn, chomp: true) do |line|
      yield(line)
    end
  end
end
