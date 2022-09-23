class ReportController < ApplicationController
  def daily
    @visits = Visit.group(:accessed_at).order(accessed_at: :desc).sum(:count)
    a = @visits.values
    @max = a.max
    @avg = a.sum(0) / a.size
  end

  def url
    @d1 = h2d(params[:d1])
    @d2 = h2d(params[:d2])
    @visits = Visit.where(:accessed_at => @d1..@d2).group(:url, :referer)
    h = @visits.sum(:count)
    @visits = h.sort_by { |k,v| -v }
    @total = @visits.sum(0) { |x| x[1] }
  end

  private

  def h2d(h)
    return Date.today if h.nil?
    Date.new(h['year'].to_i, h['month'].to_i, h['day'].to_i)
  end
end
