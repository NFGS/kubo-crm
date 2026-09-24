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

  def test_el_texto_cifrado_dice_con_que_llave_se_escribio
    cifrado = FieldCipher.encrypt("1098765432")

    assert cifrado.start_with?("v1:"), "el formato lleva la version y la llave"
    assert_equal "default", FieldCipher.key_id_of(cifrado)
    assert_equal "default", FieldCipher.current_key_id
  end

  def test_un_valor_sin_prefijo_se_descifra_con_la_llave_actual
    # Formato anterior al anillo: base64(iv|tag|ciphertext) sin version.
    heredado = FieldCipher.encrypt("1098765432").split(":", 3).last

    assert_equal "1098765432", FieldCipher.decrypt(heredado)
  end

  def test_una_llave_desconocida_no_descifra_nada
    assert_nil FieldCipher.decrypt("v1:llave-que-no-existe:AAAA")
  end

  def test_rotar_una_llave_no_pierde_el_valor
    llave_vieja = "a" * 64
    llave_nueva = "b" * 64

    ENV["KUBO_FIELD_ENCRYPTION_KEYS"] = "vieja:#{llave_vieja}"
    cifrado = FieldCipher.encrypt("1098765432")
    assert_equal "vieja", FieldCipher.key_id_of(cifrado)

    # La llave nueva entra al frente; la vieja queda para descifrar.
    ENV["KUBO_FIELD_ENCRYPTION_KEYS"] = "nueva:#{llave_nueva},vieja:#{llave_vieja}"
    assert_equal "1098765432", FieldCipher.decrypt(cifrado), "lo viejo se sigue leyendo"

    reciente = FieldCipher.encrypt("1098765432")
    assert_equal "nueva", FieldCipher.key_id_of(reciente)
    assert_equal "1098765432", FieldCipher.decrypt(reciente)
  ensure
    ENV.delete("KUBO_FIELD_ENCRYPTION_KEYS")
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
