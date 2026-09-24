require "openssl"
require "base64"

# Cifrado de campos personales (PII) con AES-256-GCM.
#
# - Confidencialidad: el valor se guarda cifrado y autenticado (GCM detecta
#   manipulaciones). Sin la llave `KUBO_FIELD_ENCRYPTION_KEY` el dato es ilegible.
# - Busqueda: se guarda un "indice ciego" (HMAC-SHA256) que permite localizar por
#   documento exacto sin descifrar ni exponer el valor.
# - Enmascarado: las listas muestran solo los ultimos caracteres.
#
# Anillo de claves (P-29, ADR-0019): el texto cifrado dice **con que llave** se
# escribio, de modo que rotar es agregar una llave al frente del anillo y
# re-cifrar los valores poco a poco, sin ventana de indisponibilidad.
#
# Formato almacenado: "v1:<key_id>:base64( iv (12 bytes) | tag (16 bytes) | ciphertext )".
# Un valor sin prefijo (anterior al anillo) se descifra con la llave actual.
class FieldCipher
  ALGORITHM = "aes-256-gcm"
  IV_LENGTH = 12
  TAG_LENGTH = 16
  HEX_KEY_LENGTH = 64

  # Valores de ejemplo de `.env.example`. Si alguien despliega copiando la
  # plantilla sin generar claves, el cifrado seria reversible por cualquiera:
  # es mejor fallar ruidosamente que proteger los datos con una clave conocida.
  PLACEHOLDER_KEYS = [("0" * HEX_KEY_LENGTH), ("f" * HEX_KEY_LENGTH)].freeze

  class << self
    def encrypt(plaintext)
      return nil if blank?(plaintext)

      key_id, material = current_key
      cipher = OpenSSL::Cipher.new(ALGORITHM)
      cipher.encrypt
      cipher.key = material
      iv = cipher.random_iv
      cipher.auth_data = ""
      ciphertext = cipher.update(plaintext.to_s) + cipher.final
      tag = cipher.auth_tag

      "#{FORMAT}:#{key_id}:#{Base64.strict_encode64(iv + tag + ciphertext)}"
    end

    # Identificador de la llave con la que se escribio un valor; nil si esta vacio.
    def key_id_of(payload)
      return nil if blank?(payload)

      split_payload(payload).first
    end

    # Llave con la que se cifra hoy (la primera del anillo).
    def current_key_id
      current_key.first
    end

    def decrypt(payload)
      return nil if blank?(payload)

      key_id, base64 = split_payload(payload)
      material = key_material(key_id)
      return nil unless material

      raw = Base64.strict_decode64(base64)
      iv = raw.byteslice(0, IV_LENGTH)
      tag = raw.byteslice(IV_LENGTH, TAG_LENGTH)
      ciphertext = raw.byteslice(IV_LENGTH + TAG_LENGTH, raw.bytesize)

      decipher = OpenSSL::Cipher.new(ALGORITHM)
      decipher.decrypt
      decipher.key = material
      decipher.iv = iv
      decipher.auth_tag = tag
      decipher.auth_data = ""
      decipher.update(ciphertext) + decipher.final
    rescue OpenSSL::Cipher::CipherError, ArgumentError
      nil
    end

    # Indice ciego: determinista y normalizado, permite buscar por igualdad.
    def blind_index(value)
      return nil if blank?(value)

      OpenSSL::HMAC.hexdigest("SHA256", blind_index_key, normalize(value))
    end

    def mask(value)
      return nil if blank?(value)

      text = value.to_s
      return "*" * text.length if text.length <= 3

      "#{'*' * (text.length - 3)}#{text[-3, 3]}"
    end

    private

    FORMAT = "v1"

    # Un valor con prefijo se descifra con la llave que lo escribio; uno sin
    # prefijo (anterior al anillo) con la llave actual.
    def split_payload(payload)
      if payload.start_with?("#{FORMAT}:")
        _, key_id, base64 = payload.split(":", 3)
        [key_id, base64]
      else
        [current_key_id, payload]
      end
    end

    def current_key
      anillo.first
    end

    # Anillo: `KUBO_FIELD_ENCRYPTION_KEYS` = "id:hex,id:hex,..." con la llave
    # nueva al frente. Sin esa variable, se usa `KUBO_FIELD_ENCRYPTION_KEY` con
    # el identificador "default" (compatibilidad con el despliegue actual).
    def anillo
      crudo = ENV["KUBO_FIELD_ENCRYPTION_KEYS"].to_s.strip
      return [["default", read_key("KUBO_FIELD_ENCRYPTION_KEY")]] if crudo.empty?

      crudo.split(",").map do |par|
        key_id, hex = par.split(":", 2)
        raise ArgumentError, "KUBO_FIELD_ENCRYPTION_KEYS debe ser id:hex separado por comas" if hex.nil?

        [key_id.strip, parse_key(hex, "KUBO_FIELD_ENCRYPTION_KEYS")]
      end
    end

    def key_material(key_id)
      anillo.find { |id, _material| id == key_id }&.last
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def normalize(value)
      value.to_s.strip.downcase.gsub(/[^a-z0-9]/, "")
    end

    def blind_index_key
      read_key("KUBO_BLIND_INDEX_KEY")
    end

    def read_key(variable)
      parse_key(ENV[variable].to_s, variable)
    end

    def parse_key(hex, variable)
      if hex.length != HEX_KEY_LENGTH
        raise ArgumentError, "#{variable} debe ser hexadecimal de 32 bytes (64 caracteres)"
      end
      if PLACEHOLDER_KEYS.include?(hex.downcase)
        raise ArgumentError,
              "#{variable} conserva el valor de ejemplo; genere una clave real con: openssl rand -hex 32"
      end

      [hex].pack("H*")
    end
  end
end
