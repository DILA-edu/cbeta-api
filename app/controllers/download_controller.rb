class DownloadController < ApplicationController
  def index
    fn = Rails.root.join('data', 'download', params[:id])
    render file: fn
  end
end
