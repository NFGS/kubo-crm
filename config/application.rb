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

    # En produccion llega por variable de entorno; en desarrollo se genera uno
    # aleatorio por arranque, de modo que nunca hay una clave en el repositorio.
    config.secret_key_base = ENV["SECRET_KEY_BASE"] || SecureRandom.hex(64)

    config.active_job.queue_adapter = :async
  end
end
