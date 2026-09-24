# Rotacion de la llave de cifrado de campos (P-29, ADR-0019).
#
# Re-cifra los valores personales con la llave actual del anillo. Es idempotente
# y por lotes: se puede correr en caliente, repetir tras una interrupcion y
# reanudar sin ventana de indisponibilidad.
#
# Un valor que no se puede descifrar NO se toca: se cuenta y se informa. La
# rotacion nunca destruye un dato que no pudo leer.
class FieldKeyRotation
  FIELDS = {
    document_number: :document_number_encrypted,
    phone: :phone_encrypted
  }.freeze

  def self.call
    # Tarea de sistema: recorre los clientes de todos los negocios. La marca
    # `app.system` la respeta la politica de RLS (migracion 000004).
    conexion = ActiveRecord::Base.connection
    conexion.execute("select set_config('app.system', 'on', false)")

    begin
      rotar
    ensure
      conexion.execute("select set_config('app.system', 'off', false)")
    end
  end

  def self.rotar
    resumen = { rotated: 0, unreadable: 0 }

    Customer.find_each(batch_size: 200) do |cliente|
      pendientes = FIELDS.filter_map do |campo, columna|
        cifrado = cliente[columna]
        next if cifrado.blank?
        next if FieldCipher.key_id_of(cifrado) == FieldCipher.current_key_id

        valor = FieldCipher.decrypt(cifrado)
        resumen[:unreadable] += 1 if valor.nil?
        [campo, valor] if valor
      end

      next if pendientes.empty?

      # Los setters del modelo re-cifran con la llave actual y recalculan el
      # indice ciego (que tambien depende de su propia llave).
      pendientes.each { |campo, valor| cliente.public_send("#{campo}=", valor) }
      cliente.save!
      resumen[:rotated] += 1
    end

    resumen
  end
end
