class CanonsController < ApplicationController
  def index
    r = []
    Canon.all.order(:id2).each do |c|
      r << {
        uuid: c.uuid,
        name: "#{c.id2} #{c.name}",
        resourceCount: Work.where(canon: c.id2).where(alt: nil).size
      }
    end
    render json: r
  end    
end
