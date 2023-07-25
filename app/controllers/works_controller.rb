class WorksController < ApplicationController
  include WorksHelper

  def index
    if params.key? :work and not params[:work].empty?
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
  end  
  
  def word_count
    r = CSV.generate(headers: true) do |csv|
      csv << %w[work cjk_chars en_words canon category]
      Work.where(alt: nil).order(:n).each do |w|
        csv << [w.n, w.cjk_chars, w.en_words, w.canon, w.category]
      end
    end
    
    send_data r, filename: "cbeta-word-count.csv"
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
    r = []
    params[:dynasty].split(',').each do |q|
      works = Work.where("time_dynasty = ?", q).order(:n)
      works.each do |w|
        r << w.to_hash
      end
    end
    r
  end
  
  def search_by_time_range
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
    c = params[:canon]
    if CBETA::VOL3.include?(c) # 冊號三碼
      pattern = "%s%03d"
    else
      pattern = "%s%02d"
    end
    v1 = pattern % [c, params[:vol_start].to_i]
    if params.key? :vol_end
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
    w1 = work_nor(c, params[:work_start])
    puts w1
    
    if params.key? :work_end
      w2 = work_nor(c, params[:work_end])
    else
      w2 = w1
    end
    
    works = Work.where(n: w1..w2).order(:n)
    r = []
    works.each do |w|
      r << w.to_hash
    end
    r
  end

  def work_nor(canon, n)
    if n.match(/^\d+$/)
      "#{canon}%04d" % n.to_i
    elsif n.match(/^(\d+)([a-zA-Z])$/)
      "#{canon}%04d#{$2}" % $1.to_i
    elsif n.match(/^([a-zA-Z])(\d+)$/)
      "#{canon}#{$1}%03d" % $2.to_i
    end
  end
end
