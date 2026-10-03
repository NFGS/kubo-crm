require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "securerandom"

Bundler.require(*Rails.groups)

module KuboCrm
  class Application < Rails::Application
    config.load_defaults 8.0

    # API pura: sin vistas, sin sesiones, sin cookies.
    config.api_only = true

    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # En produccion es obligatoria: un valor por defecto permitiria forjar
    # cookies, y una clave aleatoria por arranque invalidaria todas las sesiones
    # en cada reinicio. En desarrollo/test se genera una por proceso.
    config.secret_key_base =
      if ENV["SECRET_KEY_BASE"].present?
        ENV["SECRET_KEY_BASE"]
      elsif Rails.env.production?
        raise "SECRET_KEY_BASE es obligatoria en produccion (ver kubo-infra/.env.example)"
      else
        SecureRandom.hex(64)
      end

    config.active_job.queue_adapter = :async
  end
end
