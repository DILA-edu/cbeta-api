class WorksController < ApplicationController
  include TocNodeHelper
  include WorksHelper

  def index
    if params.key? :work and not params[:work].empty?
      unless params[:work] =~ CBETA::WORK_ID
        raise CbetaError.new(400), "work 參數 格式錯誤"
      end
      if referer_cn? and filter_cn?(id: params[:work])
        my_render EMPTY_RESULT
        return
      end
      result = get_work_info_by_id(params[:work])
      result = [result] unless result.nil?
    elsif params.key? :creator
      result = search_by_creator
    elsif params.key? :creator_id
      result = search_by_creator_id
    elsif params.key? :creator_name
      result = search_by_creator_name
    elsif params.key? :vol_start
      result = search_by_vol_range
    elsif params.key? :work_start
      result = search_by_work_range
    elsif params.key? :time_start
      result = search_by_time_range
    elsif params.key? :dynasty
      result = search_by_dynasty
    elsif params.key? :uuid # 其他方式也有 canon 參數，所以這個要排後面
      search_by_canon_uuid
      return
    end

    if referer_cn?
      result.delete_if { filter_cn?(id: it[:work]) }
    end

    if result.nil?
      r = {
        num_found: 0,
        results: [] 
      }
    else
      r = {
        num_found: result.size,
        results: result
      }
    end
    my_render(r)
  rescue CbetaError => e
    r = { error: { code: e.code, message: $! } }
    my_render(r)
  rescue => e
    r = { 
      error: { code: 500, message: $!, backtrace: e.backtrace } 
    }
    my_render(r)
  end

  def toc
    start = Time.now
    toc = get_toc_by_work_id(params[:work])
    result = toc.nil? ? [] : [toc]
    r = {
      num_found: result.size,
      time: Time.now - start,
      results: result
    }
    my_render(r)
  end
  
  private
  
  def search_by_canon_uuid
    uuid = params[:uuid]
    canon = Canon.find_by uuid: uuid
    works = Work.where(canon: canon.id2).where(alt: nil).order(:n)
    r = []
    works.each do |w|
      r << {
        uuid: w.uuid,
        name: "#{w.n} #{w.title}"
      }
    end
    render json: r
  end
  
  def search_by_creator
    q = params[:creator]
    #works = Work.where("(creators_with_id IS ?) AND (creators LIKE ?)", nil, "%#{q}%").order(:n)
    works = Work.where("creators LIKE ?", "%#{q}%").order(:n)
    r = []
    works.each do |w|
      r << w.to_hash
    end
    r
  end
  
  def search_by_creator_id
    q = params[:creator_id]
    works = Work.where("creators_with_id LIKE ?", "%#{q}%").order(:n)
    r = []
    works.each do |w|
      r << w.to_hash
    end
    r
  end
  
  # 以作譯者姓名搜尋，只搜尋還沒有 ID 的
  def search_by_creator_name
    q = params[:creator_name]
    works = Work.where("(creators_with_id IS ?) AND (creators LIKE ?)", nil, "%#{q}%").order(:n)
    r = []
    works.each do |w|
      r << w.to_hash
    end
    r
  end
  
  def search_by_dynasty
    if params[:dynasty] =~ /[a-zA-Z]/
      raise CbetaError.new(400), "dynasty 參數 格式錯誤。"
    end

    r = []
    params[:dynasty].split(',').each do |q|
      next if q.empty?
      works = Work.where("time_dynasty = ?", q).order(:n)
      works.each do |w|
        r << w.to_hash
      end
    end
    r
  end
  
  def search_by_time_range
    validate_param_int(:time_start)
    validate_param_int(:time_end)

    y1 = params[:time_start].to_i
    y2 = params[:time_end].to_i
    #works = Work.where('time_from <= ?'vol: v1..v2).order(:n)
    works = Work.where('(time_from between ? and ?) or (time_to between ? and ?)', y1, y2, y1, y2)
    
    r = []
    works.each do |w|
      r << w.to_hash
    end
    r
  end
  
  def search_by_vol_range
    unless params[:vol_start] =~ /\A\d+\z/
      raise CbetaError.new(400), "vol_start 必須是數字"
    end

    c = params[:canon]
    if CBETA::VOL3.include?(c) # 冊號三碼
      pattern = "%s%03d"
    else
      pattern = "%s%02d"
    end

    v1 = pattern % [c, params[:vol_start].to_i]
    if params.key? :vol_end
      validate_param_int(:vol_end)
      v2 = pattern % [c, params[:vol_end].to_i]
    else
      v2 = v1
    end
    
    r = []    
    works = Work.where(vol: v1..v2).order(:n)
    works.each do |w|
      r << w.to_hash
    end
    
    # 某些 佛典 跨冊，例如 T0220 的 vol 記錄為 T05..T07
    Work.where('vol LIKE ?', '%..%').each do |w|
      vol1, vol2 = w.vol.split('..')
      if (vol1 <= v1) and (vol2 >= v2)
        r << w.to_hash
      end
    end
    
    r
  end
  
  def search_by_work_range
    c = params[:canon]
    unless c.to_s.match?(CBETA::CANON_ID)
      raise CbetaError.new(400), "canon 參數 格式錯誤"
    end

    w1 = work_range_bound(c, :work_start)
    w2 = params.key?(:work_end) ? work_range_bound(c, :work_end) : w1

    works = Work.where(n: w1..w2).order(:n)
    r = []
    works.each do |w|
      r << w.to_hash
    end
    r
  end

  # 把 work_start / work_end 參數正規化成完整的典籍編號,
  # 例如 canon=T, work_start=1 => "T0001"。
  #
  # work_nor 只負責字串組裝, 組出來的結果不保證是合法的典籍編號, 所以再用
  # CBETA::WORK_ID 驗證。若少了這道檢查, 格式錯誤的參數會靜默回傳錯誤範圍的
  # 資料: 例如誤傳完整編號 work_start=T0001 (未帶 canon) 會組成 "T001",
  # 字串比較下 "T0001" < "T001", 於是 T0001~T0009 全被排除在範圍之外。
  def work_range_bound(canon, param)
    n = work_nor(canon, params[param].to_s)
    unless n&.match?(CBETA::WORK_ID)
      raise CbetaError.new(400), "#{param} 格式錯誤"
    end
    n
  end

  def work_nor(canon, n)
    if n.match(/^\d+$/)
      "#{canon}%04d" % n.to_i
    elsif n.match(/^(\d+)([a-zA-Z])$/)
      "#{canon}%04d#{$2}" % $1.to_i
    elsif n.match(/^([a-zA-Z])(\d+)$/)
      "#{canon}#{$1}%03d" % $2.to_i
    else
      nil
    end
  end
end
