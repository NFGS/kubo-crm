class HealthController < ApplicationController
  skip_before_action :require_identity

  def show
    database = "UP"
    begin
      ActiveRecord::Base.connection.execute("select 1")
    rescue StandardError => e
      Rails.logger.error("Base de datos inaccesible: #{e.message}")
      database = "DOWN"
    end

    render json: {
      status: database == "UP" ? "UP" : "DEGRADED",
      service: "kubo-crm",
      db: database,
      time: Time.current.utc.iso8601
    }
  end
end
