class ReportController < ApplicationController
  def daily
    @visits = Visit.group(:accessed_at).order(accessed_at: :desc).sum(:count)
    a = @visits.values
    @max = a.max
    @sum = a.sum(0)
    @avg = @sum / a.size
    respond_to do |format|
      format.html { render }
      format.csv { daily_csv }
    end
  end

  def url
    @d1 = h2d(params[:d1])
    @d2 = h2d(params[:d2])
    @visits = Visit.where(:accessed_at => @d1..@d2).group(:url, :referer)
    h = @visits.sum(:count)
    @visits = h.sort_by { |k,v| -v }
    @total = @visits.sum(0) { |x| x[1] }

    respond_to do |format|
      format.html { render }
      format.csv { url_csv }
    end
  end

  def referer
    @d1 = h2d(params[:d1])
    @d2 = h2d(params[:d2])
    @visits = Visit.where(:accessed_at => @d1..@d2).group(:referer)
    h = @visits.sum(:count)
    @visits = h.sort_by { |k,v| -v }
    @total = @visits.sum(0) { |x| x[1] }

    respond_to do |format|
      format.html { render }
      format.csv { referer_csv }
    end
  end

  private

  def h2d(h)
    return Date.today if h.nil?
    return Date.parse(h) if h.kind_of?(String)
    Date.new(h['year'].to_i, h['month'].to_i, h['day'].to_i)
  end

  def daily_csv
    headers = %w[date count]
    data = CSV.generate(headers: true) do |csv|
      csv << headers    
      @visits.each do |k, v|
        csv << [k, v]
      end
    end
    send_data data, filename: "cbdata-daily-#{Date.today}.csv"
  end

  def url_csv
    headers = %w[url referer count]
    data = CSV.generate(headers: true) do |csv|
      csv << headers    
      @visits.each do |a|
        csv << [a[0][0], a[0][1], a[1]]
      end
    end
    send_data data, filename: "cbdata-url-#{Date.today}.csv"
  end

  def referer_csv
    headers = %w[referer count]
    data = CSV.generate(headers: true) do |csv|
      csv << headers    
      @visits.each do |a|
        csv << [a[0], a[1]]
      end
    end
    send_data data, filename: "cbdata-referer-#{Date.today}.csv"
  end
end
