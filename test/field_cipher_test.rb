require "minitest/autorun"

ENV["KUBO_FIELD_ENCRYPTION_KEY"] ||= "a" * 64
ENV["KUBO_BLIND_INDEX_KEY"] ||= "b" * 64

require_relative "../app/services/field_cipher"

class FieldCipherTest < Minitest::Test
  def test_roundtrip_devuelve_el_valor_original
    encrypted = FieldCipher.encrypt("1098765432")

    refute_equal "1098765432", encrypted
    assert_equal "1098765432", FieldCipher.decrypt(encrypted)
  end

  def test_dos_cifrados_del_mismo_valor_son_distintos
    first = FieldCipher.encrypt("1098765432")
    second = FieldCipher.encrypt("1098765432")

    refute_equal first, second, "el IV aleatorio debe producir textos distintos"
  end

  def test_detectar_manipulacion_del_texto_cifrado
    encrypted = FieldCipher.encrypt("1098765432")
    tampered = encrypted.dup
    tampered[20] = (tampered[20] == "A" ? "B" : "A")

    assert_nil FieldCipher.decrypt(tampered), "GCM debe rechazar el dato alterado"
  end

  def test_indice_ciego_determinista_y_normalizado
    a = FieldCipher.blind_index("1.098.765.432")
    b = FieldCipher.blind_index("1098765432")

    assert_equal a, b
    assert_equal 64, a.length
  end

  def test_enmascarado_muestra_solo_los_ultimos_tres
    # El enmascarado conserva la longitud del valor original.
    assert_equal "*******432", FieldCipher.mask("1098765432")
    assert_equal "***", FieldCipher.mask("123")
    assert_equal "*****321", FieldCipher.mask("87654321")
  end

  def test_valores_vacios_no_se_cifran
    assert_nil FieldCipher.encrypt("")
    assert_nil FieldCipher.decrypt(nil)
  end

  def test_rechaza_la_clave_de_ejemplo
    original = ENV["KUBO_FIELD_ENCRYPTION_KEY"]
    ENV["KUBO_FIELD_ENCRYPTION_KEY"] = "0" * 64

    error = assert_raises(ArgumentError) { FieldCipher.encrypt("1098765432") }
    assert_match(/valor de ejemplo/, error.message)
  ensure
    ENV["KUBO_FIELD_ENCRYPTION_KEY"] = original
  end

  def test_rechaza_una_clave_de_longitud_incorrecta
    original = ENV["KUBO_FIELD_ENCRYPTION_KEY"]
    ENV["KUBO_FIELD_ENCRYPTION_KEY"] = "abc"

    assert_raises(ArgumentError) { FieldCipher.encrypt("1098765432") }
  ensure
    ENV["KUBO_FIELD_ENCRYPTION_KEY"] = original
  end
end
