# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Precompile the Doorkeeper stylesheet so its built-in views (e.g. the OAuth
# authorization error page) can render in production/staging without raising
# Sprockets::Rails::Helper::AssetNotPrecompiledError.
Rails.application.config.assets.precompile += %w[doorkeeper/application.css]
