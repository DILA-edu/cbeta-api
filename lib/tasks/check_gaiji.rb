require_relative 'cbeta_p5a_share'

class CheckGaiji

  def initialize
    @xml_root = Rails.application.config.cbeta_xml
    @gaiji = CBETA::Gaiji.new(Rails.application.config.cbeta_gaiji)
  end
  
  def check
    @errors = ''

    each_canon(@xml_root) do |c|
      check_canon(c)
    end
    
    puts @errors
  end
  
  private

  def check_canon(canon)
    src = File.join(@xml_root, canon)
    Dir["#{src}/**/*.xml"].sort.each do |fn|
      basename = File.basename(fn)
      $stderr.puts "check gaiji: #{basename}"
      doc = File.open(fn) { |f| Nokogiri::XML(f) }
      doc.remove_namespaces!
      doc.search('g').each do |e|
        gid = e['ref'][1..-1]
        if @gaiji.key? gid
          g = @gaiji[gid]
          if gid.start_with? 'CB'
            @errors << "#{basename} 缺組字式：#{gid}\n" if g['composition'].blank?
          end
        else
          @errors << "#{basename} #{gid} 不存在\n"
        end
      end
    end
  end

  include CbetaP5aShare
end