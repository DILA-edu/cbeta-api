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
      result =
        if referer_cn? and filter_cn?(id: params[:canon])
          EMPTY_RESULT
        elsif params.key? :vol
          goto_service.by_vol params
        elsif params.key? :work
          goto_service.by_work params
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
    fn = Rails.root.join('public', 'download', 'text-for-asia-network', work.canon, work.n, fn)
    
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

  def accept_all_params
    params.permit!
  end
end
