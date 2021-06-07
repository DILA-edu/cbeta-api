require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Cbdata13
  class Application < Rails::Application
    config.x.v = '1'
    config.x.ver = '1.2.24'
    config.x.q = '2021q2' # 季號
    config.x.figure_url = 'https://raw.githubusercontent.com/cbeta-git/CBR2X-figures/master'
    config.time_zone = 'Taipei'

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.0

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
  end
end
