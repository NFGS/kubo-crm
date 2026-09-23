# Clientes del negocio.
#
# Minimizacion de datos: el listado devuelve documento y telefono enmascarados;
# el detalle de un cliente concreto devuelve el valor completo.
class CustomersController < ApplicationController
  # El envoltorio automatico de Rails crea params[:customer] con solo las
  # columnas reales del modelo, y descartaria los atributos virtuales
  # (document_number, phone) que son justamente los que se cifran. Se desactiva
  # y se lee del nivel superior; el envoltorio solo se usa si el cliente lo envia.
  wrap_parameters false

  before_action :set_customer, only: %i[show update destroy]

  def index
    customers = Customer.of_tenant(current_tenant_id)
                        .by_stage(params[:stage])
                        .order(created_at: :desc)

    if params[:q].present?
      term = ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)
      customers = customers.where("name ILIKE ? OR email ILIKE ?", "%#{term}%", "%#{term}%")
    end

    render json: {
      data: customers.limit(200).map { |customer| serialize(customer, reveal: false) },
      total: customers.count
    }
  end

  def show
    render json: { data: serialize(@customer, reveal: true) }
  end

  def create
    customer = Customer.new(customer_params)
    customer.tenant_id = current_tenant_id

    if customer.save
      Rails.logger.info("customer.created id=#{customer.id} tenant=#{current_tenant_id}")
      render json: { data: serialize(customer, reveal: true) }, status: :created
    else
      render_errors(customer)
    end
  end

  def update
    if @customer.update(customer_params)
      render json: { data: serialize(@customer, reveal: true) }
    else
      render_errors(@customer)
    end
  end

  def destroy
    @customer.soft_delete!
    head :no_content
  end

  # Busqueda por documento exacto usando el indice ciego (sin descifrar).
  def stats
    scope = Customer.of_tenant(current_tenant_id)
    render json: {
      total: scope.count,
      by_stage: Customer::STAGES.index_with { |stage| scope.where(stage: stage).count },
      created_last_7_days: scope.where("created_at >= ?", 7.days.ago).count,
      total_credit_limit: scope.sum(:credit_limit).to_f
    }
  end

  private

  def set_customer
    @customer = Customer.of_tenant(current_tenant_id).find_by(id: params[:id])
    return if @customer

    render json: { code: "CUSTOMER_NOT_FOUND", message: "El cliente no existe" }, status: :not_found
  end

  def customer_params
    # Acepta el cuerpo plano o envuelto explicitamente en "customer".
    source = params[:customer].presence || params
    source.permit(
      :name, :email, :document_number, :phone, :city, :address, :stage, :notes, :credit_limit
    )
  end

  def serialize(customer, reveal:)
    {
      id: customer.id,
      name: customer.name,
      email: customer.email,
      document_number: reveal ? customer.document_number : FieldCipher.mask(customer.document_number),
      phone: reveal ? customer.phone : FieldCipher.mask(customer.phone),
      city: customer.city,
      address: customer.address,
      stage: customer.stage,
      notes: customer.notes,
      credit_limit: customer.credit_limit.to_f,
      created_at: customer.created_at.utc.iso8601,
      updated_at: customer.updated_at.utc.iso8601
    }
  end

  def render_errors(customer)
    render json: {
      code: "VALIDATION_ERROR",
      message: customer.errors.full_messages.join(", "),
      fields: customer.errors.to_hash.keys
    }, status: :unprocessable_entity
  end
end
