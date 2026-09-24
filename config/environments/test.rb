Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.cache_store = :null_store
  config.active_support.deprecation = :stderr
  config.active_record.maintain_test_schema = false
  # El esquema de la base de test se mantiene con las migraciones: no se vuelca
  # `schema.rb` (en el contenedor de pruebas el arbol va montado de solo lectura
  # y en CI ensuciaria el repositorio).
  config.active_record.dump_schema_after_migration = false
end
