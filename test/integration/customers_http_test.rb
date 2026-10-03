require_relative "../test_helper"

# Contrato HTTP del recurso de clientes: el detalle revela el valor real y el
# valor enmascarado del listado no puede pisarlo al actualizar.
class CustomersHttpTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = true

  setup do
    @tenant = SecureRandom.uuid
    @customer = con_negocio(@tenant) do
      Customer.create!(
        tenant_id: @tenant,
        name: "Cliente HTTP",
        stage: "CUSTOMER",
        document_number: "1098765432",
        phone: "3001234567"
      )
    end
  end

  test "el detalle revela el documento completo" do
    get "/api/v1/customers/#{@customer.id}", headers: { "X-Tenant-Id" => @tenant }

    assert_response :success
    assert_equal "1098765432", JSON.parse(response.body).dig("data", "document_number")
  end

  test "el valor enmascarado del listado no pisa el documento real" do
    patch "/api/v1/customers/#{@customer.id}",
          params: { name: "Cliente HTTP", document_number: "*******432", phone: "*******567" },
          headers: { "X-Tenant-Id" => @tenant },
          as: :json

    assert_response :success

    con_negocio(@tenant) do
      recargado = Customer.find(@customer.id)
      assert_equal "1098765432", recargado.document_number, "el documento real no se toca"
      assert_equal "3001234567", recargado.phone
      assert_equal recargado.id, Customer.find_by_document(@tenant, "1098765432")&.id
    end
  end

  test "el listado enmascara documento y telefono" do
    get "/api/v1/customers", headers: { "X-Tenant-Id" => @tenant }

    assert_response :success
    fila = JSON.parse(response.body)["data"].first
    assert_equal "*******432", fila["document_number"]
    assert_equal "*******567", fila["phone"]
  end

  test "la busqueda por documento usa el indice ciego" do
    get "/api/v1/customers/by-document/1098765432", headers: { "X-Tenant-Id" => @tenant }

    assert_response :success
    assert_equal @customer.id, JSON.parse(response.body).dig("data", "id")
  end

  test "un documento sin cliente responde 404" do
    get "/api/v1/customers/by-document/0000000000", headers: { "X-Tenant-Id" => @tenant }

    assert_response :not_found
  end

  test "crear un cliente devuelve el detalle" do
    post "/api/v1/customers",
         params: { name: "Cliente Nuevo", stage: "CUSTOMER", document_number: "9988776655" },
         headers: { "X-Tenant-Id" => @tenant },
         as: :json

    assert_response :created
    assert_equal "9988776655", JSON.parse(response.body).dig("data", "document_number")
  end

  test "el resumen de cartera cuenta los clientes del negocio" do
    get "/api/v1/customers/stats", headers: { "X-Tenant-Id" => @tenant }

    assert_response :success
    assert_equal 1, JSON.parse(response.body).dig("data", "total")
  end

  test "archivar un cliente lo saca del listado" do
    delete "/api/v1/customers/#{@customer.id}", headers: { "X-Tenant-Id" => @tenant }
    assert_response :no_content

    get "/api/v1/customers", headers: { "X-Tenant-Id" => @tenant }
    assert_equal 0, JSON.parse(response.body)["data"].length
  end

  test "la sonda de salud responde sin identidad" do
    get "/api/v1/health"

    assert_response :success
  end

  test "la sonda reporta DEGRADED si la base no responde" do
    rota = Object.new
    def rota.execute(*) = raise "base caida"

    original = ActiveRecord::Base.method(:connection)
    ActiveRecord::Base.define_singleton_method(:connection) { rota }

    get "/api/v1/health"

    assert_response :success
    assert_equal "DEGRADED", JSON.parse(response.body)["status"]
  ensure
    ActiveRecord::Base.define_singleton_method(:connection, original)
  end

  test "la busqueda por texto filtra por nombre o correo" do
    get "/api/v1/customers?q=HTTP", headers: { "X-Tenant-Id" => @tenant }

    assert_response :success
    assert_equal 1, JSON.parse(response.body)["data"].length

    get "/api/v1/customers?q=no-existe", headers: { "X-Tenant-Id" => @tenant }
    assert_equal 0, JSON.parse(response.body)["data"].length
  end

  test "crear con datos invalidos responde 422 con los campos" do
    post "/api/v1/customers",
         params: { name: "", stage: "CUSTOMER" },
         headers: { "X-Tenant-Id" => @tenant },
         as: :json

    assert_response :unprocessable_entity
    assert_equal "VALIDATION_ERROR", JSON.parse(response.body)["code"]
  end

  test "actualizar con datos invalidos responde 422" do
    patch "/api/v1/customers/#{@customer.id}",
          params: { stage: "BORRADO" },
          headers: { "X-Tenant-Id" => @tenant },
          as: :json

    assert_response :unprocessable_entity
    assert_equal "VALIDATION_ERROR", JSON.parse(response.body)["code"]
  end

  test "un cliente inexistente responde 404" do
    get "/api/v1/customers/#{SecureRandom.uuid}", headers: { "X-Tenant-Id" => @tenant }

    assert_response :not_found
    assert_equal "CUSTOMER_NOT_FOUND", JSON.parse(response.body)["code"]
  end

  test "un negocio malformado responde 400 y sin identidad 401" do
    get "/api/v1/customers", headers: { "X-Tenant-Id" => "no-es-uuid" }
    assert_response :bad_request
    assert_equal "INVALID_TENANT", JSON.parse(response.body)["code"]

    get "/api/v1/customers"
    assert_response :unauthorized
    assert_equal "UNAUTHENTICATED", JSON.parse(response.body)["code"]
  end

  private

  def con_negocio(tenant_id)
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array(
        ["select set_config('app.tenant_id', ?, true)", tenant_id.to_s]
      )
    )
    yield
  end
end
