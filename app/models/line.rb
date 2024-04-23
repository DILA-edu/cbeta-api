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

  def self.get_linehead_by_vol(args)
    canon = args[:canon]
    vol = CBETA.normalize_vol(canon + args[:vol])
    
    if args.key?(:work)
      work_id = args[:canon] + Work.normalize_no(args[:work])
    end

    if args.key?(:page)
      page = "%04d" % args[:page].to_i
      if args.key?(:col)
        line = Line.where(vol: vol, page: page, col: args[:col]).first
        return line.linehead
      end

      line = Line.where(vol: vol, page: page).first
      return line.linehead
    end

    if work_id.nil?
      work_id = JuanLine.find_by_vol(vol).first
    end
    
    file = Work.first_file_in_vol(work_id, vol)
    self.construct_linehead(work_id, file, lb)
  end

  def self.get_lb(args)
    page = args[:page]
    if page.match(/^([a-z])(\d+)$/)
      page = $1 + $2.rjust(3, '0')
    elsif page.match(/^\d+$/)
      page = page.rjust(4, '0')
    else
      raise CbetaError.new(400), "頁碼格式錯誤：#{args[:page]}"
    end

    if args.key?(:work_id) and args.key?(:juan)
      vol, start_lb = JuanLine.get_first_lb_by_work_juan(args[:work_id], args[:juan])
      start_page = start_lb.sub(/^(\d{4}).*$/, '\1')
      if page < start_page
        raise CbetaError.new(400), "頁碼小於起始頁碼, 佛典編號: #{args[:work_id]}, 卷號: #{args[:juan]}, 起始頁碼: #{start_lb}, 要求頁碼: #{page}" 
      end
    end

    lb = page
    if args[:col].nil?
      lb += 'a01'
    else
      col = args[:col]
      unless col.match(/^[a-z]$/)
        raise CbetaError.new(400), "欄號格式錯誤: #{col}"
      end
      lb << col
      if args[:line].nil?
        lb << '01'
        if not args.key?(:vol) or args[:vol] == vol
          lb = start_lb if lb < start_lb
        end
      else
        line = args[:line]
        unless line.match(/^\d+$/)
          raise CbetaError.new(400), "行號格式錯誤: #{line}"
        end
        lb << line.rjust(2, '0')
      end
    end

    if args.key?(:vol) and args.key?(:work_id)
      juan = JuanLine.get_juan_by_vol_work_lb(args[:vol], args[:work_id], lb)
      if juan.nil?
        raise CbetaError.new(400), "冊號、典籍編號、行號 不符: vol: #{args[:vol]}, work: #{args[:work_id]}, lb: #{lb}" 
      end
    end

    lb
  end
end
