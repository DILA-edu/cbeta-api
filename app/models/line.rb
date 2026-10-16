class Line < ActiveRecord::Base
  def self.construct_linehead(work, file, lb)
    if work == 'T0220'
      file.sub(/[a-z]$/, '') + '_p' + lb
    elsif work.match(/[a-zA-Z]$/)
      file + 'p' + lb
    else
      file + '_p' + lb
    end
  end

  def self.find_by_vol_lb(vol, lb)
    page = lb[0, 4]
    col = lb[4]
    line_no = lb[-2..-1]

    line = Line.find_by(vol: vol, page:, col:, line: line_no)

    if line.nil?
      s = "Line record 不存在: vol: #{vol}, lb: #{lb}, page: #{page}, col: #{col}, line: #{line_no}"
      raise CbetaError.new(404), s
    end

    line
  end

  def self.find_by_vol_params(args)
    canon = args[:canon]

    data = { vol: CBETA.normalize_vol(canon + args[:vol]) }
    
    if args.key?(:page)
      if args[:page].match?(/^\d+$/)
        data[:page] = "%04d" % args[:page].to_i
      else
        m = args[:page].match(/^([a-z])(\d+)$/)
        raise CbetaError.new(404), "頁碼格式錯誤: #{args[:page]}" if m.nil?
        data[:page] = "#{$1}%03d" % $2.to_i
      end
      if args.key?(:col)
        data[:col] = args[:col]
        if args.key?(:line)
          data[:line] = "%02d" % args[:line].to_i
        end
      end
    end

    line = Line.find_by(data)

    if line.nil?
      s = "Line record 不存在: args: #{args}"
      raise CbetaError.new(404), s
    end

    line
  end
end
