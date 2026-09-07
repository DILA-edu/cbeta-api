require 'will_paginate/array'

# 流量報表限管理者。
#
# daily / url / referer 揭露全站流量與 referer 明細
# (Visit.group(:url, :referer)),等於公開「誰在用、從哪來」;
# 且為全表 group by sum,本身也是施力點。
#
# index 例外開放: 它是「字數統計」JSON 的欄位說明頁,不含任何流量資料,
# 而且從公開的 static_pages/report 連過去。
# (設計文件 7.4 已預留「個別報表可開放給非管理者」的空間。)
#
# 使用者「自己的」統計不在此限,在帳號頁,見 AccountsController。
#
# 繼承 WebController: 報表需要登入,而 ApplicationController 是關閉 CSRF 的
# stateless API base。
#
# 見 doc/api-key-design.md 7.4
class ReportController < WebController
  before_action :require_admin!, except: :index

  def daily
    @visits = Visit.group(:accessed_at).order(accessed_at: :desc).sum(:count)
    a = @visits.values
    @max = a.max
    @sum = a.sum(0)
    @avg = @sum / a.size
    
    @visit_keys = @visits.keys.paginate(page: params[:page])

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
      format.html
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
      format.html
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
