Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  config.cache_store = :memory_store

  config.active_support.deprecation = :log
  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = false
  config.active_job.verbose_enqueue_logs = false

  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
end
