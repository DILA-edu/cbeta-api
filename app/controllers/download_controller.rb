class DownloadController < ApplicationController
  def index
    fn = Rails.root.join('data', 'download', params[:id])
    send_file(fn)
  end
end
