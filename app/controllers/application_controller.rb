class ApplicationController < ActionController::API
  # El interceptor de tenant (P-02) envuelve cada accion en una transaccion con
  # `app.tenant_id` fijado: la politica de RLS de PostgreSQL filtra por negocio
  # aunque una consulta olvide el `where`.
  around_action :with_tenant_rls

  before_action :require_identity

  rescue_from ActionController::ParameterMissing do |exception|
    render json: {
      code: "VALIDATION_ERROR",
      message: "Falta el parametro #{exception.param}"
    }, status: :bad_request
  end

  private

  # `set_config(..., true)` es local a la transaccion: la variable desaparece al
  # terminar y no puede filtrarse a otra peticion que reutilice la conexion.
  def with_tenant_rls(&action)
    tenant = current_tenant_id
    if tenant.present?
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array(
            ["select set_config('app.tenant_id', ?, true)", tenant]
          )
        )
        action.call
      end
    else
      action.call
    end
  end

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
