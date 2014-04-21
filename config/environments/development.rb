Badgiy::Application.configure do
  config.action_controller.perform_caching = false
  config.action_dispatch.best_standards_support = :builtin
  config.action_mailer.delivery_method = :letter_opener
  config.action_mailer.raise_delivery_errors = false
  config.active_support.deprecation = :log
  config.assets.compile = true
  config.assets.compress = false
  config.assets.debug = true
  config.cache_classes = false
  config.consider_all_requests_local = true
  config.host = 'localhost:3000'
  config.serve_static_assets = false
  config.whiny_nils = true
end
