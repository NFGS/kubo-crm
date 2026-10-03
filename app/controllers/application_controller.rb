class ApplicationController < ActionController::API
  # Formato de las cabeceras de identidad: un valor malformado no debe llegar a
  # `set_config('app.tenant_id')`, donde provocaria un error de conversion.
  UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  # El interceptor de tenant (P-02) envuelve cada accion en una transaccion con
  # `app.tenant_id` fijado: la politica de RLS de PostgreSQL filtra por negocio
  # aunque una consulta olvide el `where`.
  around_action :with_tenant_rls

  before_action :require_identity

  # Defensivo: ningun controlador usa `params.require` hoy; si se añade, el
  # error se traduce a 400 en lugar de un 500.
  # :nocov:
  rescue_from ActionController::ParameterMissing do |exception|
    render json: {
      code: "VALIDATION_ERROR",
      message: "Falta el parametro #{exception.param}"
    }, status: :bad_request
  end
  # :nocov:

  private

  # `set_config(..., true)` es local a la transaccion: la variable desaparece al
  # terminar y no puede filtrarse a otra peticion que reutilice la conexion.
  def with_tenant_rls(&action)
    tenant = current_tenant_id
    if tenant.present? && tenant.match?(UUID_FORMAT)
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
    tenant = current_tenant_id

    if tenant.present? && !tenant.match?(UUID_FORMAT)
      render json: {
        code: "INVALID_TENANT",
        message: "El negocio indicado no es valido"
      }, status: :bad_request
      return
    end

    return if tenant.present?

    render json: {
      code: "UNAUTHENTICATED",
      message: "La peticion no trae identidad verificada"
    }, status: :unauthorized
  end

  def current_tenant_id
    request.headers["X-Tenant-Id"].presence
  end
end
