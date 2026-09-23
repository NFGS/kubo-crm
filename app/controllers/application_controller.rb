class ApplicationController < ActionController::API
  before_action :require_identity

  rescue_from ActionController::ParameterMissing do |exception|
    render json: {
      code: "VALIDATION_ERROR",
      message: "Falta el parametro #{exception.param}"
    }, status: :bad_request
  end

  private

  # La identidad llega ya verificada desde el API Gateway.
  def require_identity
    return if current_tenant_id.present?

    render json: {
      code: "UNAUTHENTICATED",
      message: "La peticion no trae identidad verificada"
    }, status: :unauthorized
  end

  def current_tenant_id
    request.headers["X-Tenant-Id"].presence
  end

  def current_user_id
    request.headers["X-User-Id"].presence
  end
end
