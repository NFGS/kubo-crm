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

  test "la rotacion re-cifra los valores con la llave nueva (P-29)" do
    ENV["KUBO_FIELD_ENCRYPTION_KEYS"] = "vieja:#{'a' * 64}"
    cliente = crear_cliente(@tenant, "1098765432", telefono: "3001234567")
    viejo = con_negocio(@tenant) { Customer.find(cliente.id).document_number_encrypted }

    assert_equal "vieja", FieldCipher.key_id_of(viejo)

    # Entra la llave nueva al frente; la vieja queda para descifrar.
    ENV["KUBO_FIELD_ENCRYPTION_KEYS"] = "nueva:#{'b' * 64},vieja:#{'a' * 64}"
    resumen = FieldKeyRotation.call

    assert_operator resumen[:rotated], :>=, 1
    assert_equal 0, resumen[:unreadable]

    con_negocio(@tenant) do
      recargado = Customer.find(cliente.id)

      assert_equal "nueva", FieldCipher.key_id_of(recargado.document_number_encrypted)
      assert_equal "1098765432", recargado.document_number
      assert_equal "3001234567", recargado.phone
      # El indice ciego se recalculo: la busqueda sigue encontrando al cliente.
      assert_equal recargado.id, Customer.find_by_document(@tenant, "1098765432")&.id
    end
  ensure
    ENV.delete("KUBO_FIELD_ENCRYPTION_KEYS")
  end

  test "la rotacion re-cifra los valores anteriores al anillo (P-29)" do
    # Valor escrito antes del anillo: sin prefijo, con la llave unica.
    cliente = crear_cliente(@tenant, "1098765432", telefono: "3001234567")
    sin_prefijo = con_negocio(@tenant) do
      fila = Customer.find(cliente.id)
      {
        documento: fila.document_number_encrypted.split(":", 3).last,
        telefono: fila.phone_encrypted.split(":", 3).last
      }
    end
    con_negocio(@tenant) do
      Customer.find(cliente.id).update_columns(
        document_number_encrypted: sin_prefijo[:documento],
        phone_encrypted: sin_prefijo[:telefono]
      )
    end

    # La llave nueva entra al frente; la unica sigue disponible como "default"
    # (KUBO_FIELD_ENCRYPTION_KEY no cambia), de modo que el heredado se puede
    # descifrar y re-cifrar en vez de quedar ilegible para siempre.
    ENV["KUBO_FIELD_ENCRYPTION_KEYS"] = "nueva:#{'b' * 64}"
    resumen = FieldKeyRotation.call

    assert_operator resumen[:rotated], :>=, 1
    assert_equal 0, resumen[:unreadable]

    con_negocio(@tenant) do
      recargado = Customer.find(cliente.id)

      assert_equal "nueva", FieldCipher.key_id_of(recargado.document_number_encrypted)
      assert_equal "1098765432", recargado.document_number
      assert_equal "3001234567", recargado.phone
      assert_equal recargado.id, Customer.find_by_document(@tenant, "1098765432")&.id
    end
  ensure
    ENV.delete("KUBO_FIELD_ENCRYPTION_KEYS")
  end

  test "la rotacion recalcula el indice ciego si cambio su llave (P-29)" do
    cliente = crear_cliente(@tenant, "1098765432")

    # Cambiar la llave del indice ciego invalida las busquedas por igualdad; la
    # rotacion lo detecta y vuelve a calcularlo aunque la llave de cifrado no
    # haya cambiado.
    ENV["KUBO_BLIND_INDEX_KEY"] = "c" * 64
    resumen = FieldKeyRotation.call

    assert_operator resumen[:rotated], :>=, 1
    assert_equal 0, resumen[:unreadable]

    con_negocio(@tenant) do
      assert_equal cliente.id, Customer.find_by_document(@tenant, "1098765432")&.id
    end
  ensure
    ENV["KUBO_BLIND_INDEX_KEY"] = "b" * 64
  end

  test "un valor ilegible se cuenta y no se destruye (P-29)" do
    cliente = crear_cliente(@tenant, "1098765432")
    con_negocio(@tenant) do
      Customer.find(cliente.id).update_columns(document_number_encrypted: "v1:default:no-es-base64")
    end

    resumen = FieldKeyRotation.call

    assert_operator resumen[:unreadable], :>=, 1
    con_negocio(@tenant) do
      assert_equal "v1:default:no-es-base64", Customer.find(cliente.id).document_number_encrypted
    end
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
