class JuansController < ApplicationController
  include TocNodeHelper
  include WorksHelper
  
  before_action :accept_all_params
  
  def index
    work = params[:work]
    
    if referer_cn? and filter_cn?(id: work)
      my_render EMPTY_RESULT
      return
    end

    canon = CBETA.get_canon_id_from_work_id(work)
    i = params[:juan].to_i
    juan_line = JuanLine.find_by(work: work, juan: i)
    juan = "%03d" % i
    fn = Rails.root.join('data', 'html', canon, work, juan+'.html')

    if File.exist? fn
      html = File.read(fn)
      r = {
        num_found: 1,
        uuid: juan_line.uuid,
        content: juan_line.content_uuid,
        results: [html]
      }
      r[:toc] = get_toc_by_work_id(work) if params[:toc]=='1'
      r[:work_info] = get_work_info_by_id(work) if params[:work_info]=='1'
    else
      r = EMPTY_RESULT
    end

    my_render r
  end
  
  def goto
    result = nil
    if params.key? :linehead
      result = goto_linehead params
    elsif params.key? :canon
      if params.key?(:work)
        w = Work.normalize_no(params[:work])
        @work_id = params[:canon] + w
      end  
      result = 
        if referer_cn? and filter_cn?(id: params[:canon])
          EMPTY_RESULT
        elsif params.key? :vol
          goto_by_vol params
        elsif params.key? :work
          goto_by_work params
        end
    end
    
    if result.nil?
      r = { 
        error: { code: 520, message: "Unknown Error" }
      }
    elsif result.key?(:error)
      r = result
    elsif result.key?(:work)
      w = Work.find_by n: result[:work]      
      if w.nil?
        logger.error "work id 在 work table 中不存在：#{result[:work]}"
      else
        result['title'] = w.title
      end
      r = {
        num_found: 1,
        results: [result]
      }
    else
      r = result
    end
    
    my_render(r)
  rescue CbetaError => e
    r = { error: { code: e.code, message: $!, backtrace: e.backtrace } }
    my_render(r)
  rescue => e
    r = { 
      error: { code: 500, message: $!, backtrace: e.backtrace } 
    }
    my_render(r)
  end
  
  def list_for_asia_network
    uuid = params[:uuid]
    work = Work.find_by uuid: uuid
    juans = JuanLine.where(work: work.n).order(:juan)
    
    r = []
    juans.each do |j|
      r << {
        uuid: j.uuid,
        title: "#{work.n} #{work.title} 第#{j.juan}卷",
        parentUuid: nil,
        uri: "http://cbetaonline.dila.edu.tw/#{work.n}_%03d" % j.juan,
        contentUnitCount: 1
      }
    end
    render json: r
  end
  
  def content_for_asia_network
    uuid = params[:uuid]
    juan = JuanLine.find_by uuid: uuid
    work = Work.find_by n: juan.work
    
    fn = "#{work.n}_%03d.txt" % juan.juan
    fn = Rails.root.join('data', 'download', 'text-for-asia-network', work.canon, work.n, fn)
    
    if File.exist? fn
      s = File.read(fn)
    
      r = [
        {
          uuid: juan.content_uuid,
          title: "#{work.n} #{work.title} 第#{juan.juan}卷",
          contents: s
        }
      ]
    else
      r = { 
        error: 'file not found',
        file_path: fn
      }
    end
    
    render json: r
  end
  
  def show_for_asia_network
    uuid = params[:uuid]
    juan = JuanLine.find_by uuid: uuid
    work = Work.find_by n: juan.work
    
    uri = File.join(root_url, 'download', 'text-for-asia-network', work.canon, work.n, "#{work.n}_%03d.txt" % juan.juan)
    
    r = {
      uuid: juan.content_uuid,
      title: "#{work.n} #{work.title} 第#{juan.juan}卷",
      parentUuid: nil,
      uri: uri,
      contentUnitCount: 1
    }
    render json: r
  end
  
  private
  
  # goto 書本結構
  def goto_by_vol(opts)
    canon = opts[:canon]
    @vol = opts[:vol]
    @vol = CBETA.normalize_vol(canon + @vol)
    
    if opts.key? :page
      lb = lb_from_params opts
      w, juan = JuanLine.find_by_vol_lb(@vol, lb)
    else
      w, juan, lb = JuanLine.find_by_vol(@vol)
    end

    work = @work_id || w
    
    file = Work.first_file_in_vol(work, @vol)
    { vol: @vol, work: work, file: file, juan: juan, lb: lb }
  end
  
  # goto 經卷結構
  def goto_by_work(params)
    canon = params[:canon]
    
    work = Work.find_by n: @work_id
    if work.nil?
      return { 
        error: { code: 404, message: "Work ID (佛典編號) not found: #{@work_id}" }
      }
    end
    
    file = work.first_file
    @vol = file.sub(/^(.*?)n.*$/, '\1')
    
    if params.key? :juan
      @juan = params[:juan].to_i
    else
      @juan = work.juan_start
    end
    
    if params.key? :page
      lb = lb_from_params params
      unless params.key? :juan
        @juan = JuanLine.find_by_vol_lb(@vol, lb)[1]
      end
    else
      @vol, lb = JuanLine.get_first_lb_by_work_juan(@work_id, @juan)
    end
    
    lh = CBETA.get_linehead(file, lb)
    r = Line.find_by linehead: lh
    if r.nil?
      s = "行首資訊不存在: #{lh}, vol: #{@vol}, juan: #{@juan}, lb: #{lb}"
      raise CbetaError.new(404), s
    end

    { vol: @vol, work: @work_id, file: file, juan: @juan, lb: lb }
  end
  
  def lb_from_params(params)
    logger.debug 'lb_from_params'
    logger.debug "page: #{params[:page]}"

    page = params[:page]
    if page.match(/^([a-z])(\d+)$/)
      page = $1 + $2.rjust(3, '0')
    elsif page.match(/^\d+$/)
      page = page.rjust(4, '0')
    else
      raise CbetaError.new(400), "頁碼格式錯誤：#{params[:page]}"
    end

    if @work_id.nil? or @juan.nil?
    else
      vol, start_lb = JuanLine.get_first_lb_by_work_juan(@work_id, @juan)
      start_page = start_lb.sub(/^(\d{4}).*$/, '\1')
      if page < start_page
        raise CbetaError.new(400), "頁碼小於起始頁碼, 佛典編號: #{@work_id}, 卷號: #{@juan}, 起始頁碼: #{start_lb}, 要求頁碼: #{page}" 
      end
    end

    logger.debug "page: #{page}"
    lb = page
    if params[:col].nil?
      lb += 'a01'
    else
      col = params[:col]
      unless col.match(/^[a-z]$/)
        raise CbetaError.new(400), "欄號格式錯誤: #{col}"
      end
      lb += col
      if params[:line].nil?
        lb += '01'
        if not params.key?(:vol) or params[:vol] == vol
          lb = start_lb if lb < start_lb
        end
      else
        line = params[:line]
        unless line.match(/^\d+$/)
          raise CbetaError.new(400), "行號格式錯誤: #{line}"
        end
        lb += line.rjust(2, '0')
      end
    end
    logger.debug "juans_controller.rb, Line: #{__LINE__}, lb: #{lb}"

    unless @vol.nil? or @work_id.nil?
      juan = JuanLine.get_juan_by_vol_work_lb(@vol, @work_id, lb)
      if juan.nil?
        raise CbetaError.new(400), "冊號、典籍編號、行號 不符: vol: #{@vol}, work: #{@work_id}, lb: #{lb}" 
      end
    end

    lb
  end

  def accept_all_params
    params.permit!
  end
end
