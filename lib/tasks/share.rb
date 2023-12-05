class MyCbetaShare
  attr_reader :canons

  def initialize
    fn = File.join(Rails.application.config.cbeta_data, 'canons.yml')
    @canons = YAML.load_file(fn)
  end

  def self.cbeta_juan_declare(args)
    args.with_defaults!(format: :text)

    r = if args[:format] == :text
          "#%s\n" % ('-' * 70)
        else
          "<div id='cbeta-copyright'><p>\n"
        end

    # 處理 卷跨冊
    case args[:work]
    when 'L1557' 
      case args[:vol]
      when 'L131'
        v = '130-131' if args[:juan] == 17
      when 'L132'
        v = '131-132' if args[:juan] == 34
      when 'L133'
        v = '132-133' if args[:juan] == 51
      end
    when 'X0714'
      v = '39-40' if args[:vol] == 'X40' and args[:juan] == 3
    end

    c = args[:canon]
    c_name = args[:canon_name]
    source = "「#{args[:source_desc]}」"
    v ||= args[:vol].sub(/^#{c}0*(.*)$/, '\1')    
    n = args[:work].sub(/^#{c}0*([^0].*)$/, '\1')
    prefix = args[:format] == :text ? '#' : ''

    lines = []
    lines << "#{prefix}【經文資訊】#{c_name} 第 #{v} 冊 No. #{n} #{args[:title]}"
    lines << "#{prefix}【版本記錄】發行日期：#{args[:publish]}，最後更新：#{args[:updated_at]}"
    lines << "#{prefix}【編輯說明】本資料庫由 財團法人佛教電子佛典基金會（CBETA）依#{source}所編輯"
    lines << "#{prefix}【原始資料】#{args[:contributors]}"

    lines.each do |s|
      r << s
      r << "<br>" if args[:format] == :html
      r << "\n"
    end

    case args[:format]
    when :text
      r << "#【其他事項】本資料庫可自由免費流通，詳細內容請參閱【財團法人佛教電子佛典基金會資料庫版權宣告】\n"
      r << "#%s\n\n" % ('-' * 70)
    when :html
      r << "【其他事項】詳細說明請參閱【<a href='http://www.cbeta.org/copyright.php' target='_blank'>財團法人佛教電子佛典基金會資料庫版權宣告</a>】\n"
      r << "</p></div><!-- end of cbeta-copyright -->\n"  
    end

    r
  end

  def self.get_cbeta_gaiji
    folder = Rails.application.config.cbeta_gaiji
    fn = File.join(folder, 'cbeta_gaiji.json')
    s = File.read(fn)
    JSON.parse(s)
  end
  
  def self.get_cbeta_gaiji_skt
    folder = Rails.application.config.cbeta_gaiji
    fn = File.join(folder, 'cbeta_sanskrit.json')
    s = File.read(fn)
    JSON.parse(s)
  end
  
  def self.get_update_date(xml_fn)
    folder = File.dirname(xml_fn)
    basename = File.basename(xml_fn)
    r = nil
    Dir.chdir(folder) do
      s = `git log -1 --pretty=format:"%ai" #{basename}`
      r = s.sub(/^(\d{4}\-\d\d\-\d\d).*$/, '\1')
    end
    r
  end
  
  def self.get_work_categories
    r = {}
    folder = Rails.configuration.x.work_info
    Dir.glob("#{folder}/*.json") do |f|
      works = JSON.load_file(f)
      works.each do |k, h|
        r[k] = h['category']
      end
    end
    r
  end  

  def get_canon_name(id)
    @canons[id]['zh']
  end
end
