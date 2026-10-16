class CanonsController < ApplicationController
  include ApiKeyAuthentication

  def index
    with_release_etag { render_index }
  end

  private

  def render_index
    r = []
    # 一次 GROUP BY 取得各藏經的佛典數, 免得每個 canon 查一次
    counts = Work.where(alt: nil).group(:canon).count
    Canon.all.order(:id2).each do |c|
      r << {
        uuid: c.uuid,
        name: "#{c.id2} #{c.name}",
        resourceCount: counts.fetch(c.id2, 0)
      }
    end
    render json: r
  end    
end
