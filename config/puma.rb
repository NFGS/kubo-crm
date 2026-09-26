threads_count = ENV.fetch("RAILS_MAX_THREADS", 5).to_i
threads threads_count, threads_count

# Malla interna (P-28, ADR-0020): con KUBO_INTERNAL_TLS=true Puma sirve HTTPS y
# exige el certificado del cliente; sin la bandera, HTTP normal.
if ENV["KUBO_INTERNAL_TLS"] == "true"
  ssl_bind "0.0.0.0", ENV.fetch("PORT", 8082),
           cert: ENV.fetch("KUBO_TLS_CERT"),
           key: ENV.fetch("KUBO_TLS_KEY"),
           ca: ENV.fetch("KUBO_TLS_CA"),
           verify_mode: "peer"
else
  port ENV.fetch("PORT", 8082)
end
environment ENV.fetch("RAILS_ENV", "development")

# El sistema corre en el local del negocio: pocos procesos y memoria acotada.
workers ENV.fetch("WEB_CONCURRENCY", 0).to_i
preload_app! if ENV.fetch("WEB_CONCURRENCY", 0).to_i.positive?

plugin :tmp_restart
