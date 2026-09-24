require_relative "../test_helper"

# Integracion contra PostgreSQL real (P-08).
#
# La politica RLS y el cifrado de campos personales solo se pueden verificar con
# el motor delante: una prueba pura puede comprobar que el texto cifrado no
# contiene el original, pero no que la politica aisle negocios ni que el indice
# ciego encuentre la fila sin descifrar.
#
# Se ejecuta como el rol de la aplicacion (`kubo_crm`), no como superusuario:
# los superusuarios ignoran RLS incluso con FORCE.
class RlsAndCipherTest < ActiveSupport::TestCase
  # Cada prueba corre en una transaccion que se revierte: la base de test queda
  # limpia sin borrar filas a mano.
  self.use_transactional_tests = true

  def setup
    @tenant = SecureRandom.uuid
    @otro = SecureRandom.uuid
  end

  test "sin contexto de negocio la politica no devuelve filas" do
    crear_cliente(@tenant, "1098765432")

    assert_equal 0, con_negocio(nil) { Customer.count }
    assert_equal 0, con_negocio(@otro) { Customer.count }
    assert_equal 1, con_negocio(@tenant) { Customer.count }
  end

  test "el documento se guarda cifrado y se busca por indice ciego" do
    cliente = crear_cliente(@tenant, "1098765432", telefono: "3001234567")

    fila = con_negocio(@tenant) do
      ActiveRecord::Base.connection.select_one(
        ActiveRecord::Base.sanitize_sql_array(
          [
            "select document_number_encrypted, document_number_bidx, phone_encrypted " \
            "from customers where id = ?",
            cliente.id
          ]
        )
      )
    end

    refute_includes fila["document_number_encrypted"].to_s, "1098765432",
                    "el documento no debe quedar en claro en la base"
    refute_includes fila["phone_encrypted"].to_s, "3001234567",
                    "el telefono no debe quedar en claro en la base"
    assert_equal FieldCipher.blind_index("1098765432"), fila["document_number_bidx"]

    encontrado = con_negocio(@tenant) { Customer.find_by_document(@tenant, "1098765432") }
    assert_equal cliente.id, encontrado&.id
    assert_equal "1098765432", encontrado.document_number
    assert_equal "3001234567", encontrado.phone

    # El indice ciego tampoco cruza negocios.
    assert_nil con_negocio(@otro) { Customer.find_by_document(@otro, "1098765432") }
  end

  private

  def crear_cliente(tenant, documento, telefono: nil)
    con_negocio(tenant) do
      Customer.create!(
        tenant_id: tenant,
        name: "Cliente Integracion",
        stage: "CUSTOMER",
        document_number: documento,
        phone: telefono
      )
    end
  end

  # Replica el interceptor del controlador, que fija `app.tenant_id` con
  # `set_config(..., true)` (local a la transaccion) antes de cada accion. Aqui
  # la prueba ya vive dentro de su propia transaccion, asi que cada llamada
  # vuelve a fijar el valor de forma explicita (con nil lo limpia, que es el
  # estado de una peticion sin negocio).
  def con_negocio(tenant_id)
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array(
        ["select set_config('app.tenant_id', ?, true)", tenant_id.to_s]
      )
    )
    yield
  end
end
