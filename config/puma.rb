threads_count = ENV.fetch("RAILS_MAX_THREADS", 5).to_i
threads threads_count, threads_count

port ENV.fetch("PORT", 8082)
environment ENV.fetch("RAILS_ENV", "development")

# El sistema corre en el local del negocio: pocos procesos y memoria acotada.
workers ENV.fetch("WEB_CONCURRENCY", 0).to_i
preload_app! if ENV.fetch("WEB_CONCURRENCY", 0).to_i.positive?

plugin :tmp_restart
