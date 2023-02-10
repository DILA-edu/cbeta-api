class DownloadController < ApplicationController
  def index
    fn = Rails.root.join('data', 'download', params[:id])
    logger.info "download_controller.rb, fn: #{fn}"
    if File.file?(fn) and File.readable?(fn)
      send_file(fn)
    else
      my_render_error(404, "File not found.")
    end
  rescue => e
    my_render_error(500, $!)
  end
end
