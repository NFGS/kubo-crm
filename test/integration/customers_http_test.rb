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
