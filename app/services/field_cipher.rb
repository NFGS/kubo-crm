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
# Formato almacenado: base64( iv (12 bytes) | tag (16 bytes) | ciphertext )
class FieldCipher
  ALGORITHM = "aes-256-gcm"
  IV_LENGTH = 12
  TAG_LENGTH = 16
  HEX_KEY_LENGTH = 64

  class << self
    def encrypt(plaintext)
      return nil if blank?(plaintext)

      cipher = OpenSSL::Cipher.new(ALGORITHM)
      cipher.encrypt
      cipher.key = encryption_key
      iv = cipher.random_iv
      cipher.auth_data = ""
      ciphertext = cipher.update(plaintext.to_s) + cipher.final
      tag = cipher.auth_tag

      Base64.strict_encode64(iv + tag + ciphertext)
    end

    def decrypt(payload)
      return nil if blank?(payload)

      raw = Base64.strict_decode64(payload)
      iv = raw.byteslice(0, IV_LENGTH)
      tag = raw.byteslice(IV_LENGTH, TAG_LENGTH)
      ciphertext = raw.byteslice(IV_LENGTH + TAG_LENGTH, raw.bytesize)

      decipher = OpenSSL::Cipher.new(ALGORITHM)
      decipher.decrypt
      decipher.key = encryption_key
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

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def normalize(value)
      value.to_s.strip.downcase.gsub(/[^a-z0-9]/, "")
    end

    def encryption_key
      hex = ENV["KUBO_FIELD_ENCRYPTION_KEY"].to_s
      if hex.length != HEX_KEY_LENGTH
        raise ArgumentError, "KUBO_FIELD_ENCRYPTION_KEY debe ser hexadecimal de 32 bytes (64 caracteres)"
      end

      [hex].pack("H*")
    end

    def blind_index_key
      hex = ENV["KUBO_BLIND_INDEX_KEY"].to_s
      if hex.length != HEX_KEY_LENGTH
        raise ArgumentError, "KUBO_BLIND_INDEX_KEY debe ser hexadecimal de 32 bytes (64 caracteres)"
      end

      [hex].pack("H*")
    end
  end
end
