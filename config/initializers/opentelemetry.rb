# Trazas OpenTelemetry (P-07).
#
# Solo se activan cuando `OTEL_EXPORTER_OTLP_ENDPOINT` esta definido: sin
# collector el servicio arranca igual y no intenta exportar. `use_all` activa la
# instrumentacion de Rails (peticiones, ActiveRecord y plantillas).
return if ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].blank?

require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"

OpenTelemetry::SDK.configure do |config|
  config.service_name = "kubo-crm"
  config.use_all
end
