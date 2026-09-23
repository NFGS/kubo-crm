Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false

  config.cache_store = :memory_store
  config.active_support.deprecation = :notify
  config.active_record.dump_schema_after_migration = false
  config.active_job.verbose_enqueue_logs = false

  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.log_tags = [:request_id]

  # TLS termina en el proxy inverso del despliegue; el servicio habla HTTP en la
  # red privada de contenedores.
  config.force_ssl = false
end
