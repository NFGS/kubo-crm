# Arranque comun de las pruebas del CRM.
#
# Las pruebas de integracion (P-08) necesitan ActiveRecord contra PostgreSQL
# real, asi que aqui se carga el entorno de Rails una sola vez. La prueba pura
# de cifrado (`test/field_cipher_test.rb`) sigue siendo independiente y no
# requiere este archivo.
ENV["RAILS_ENV"] ||= "test"

# Claves de ejemplo para las pruebas: el cifrado exige 64 digitos hexadecimales
# y rechaza los valores de la plantilla.
ENV["KUBO_FIELD_ENCRYPTION_KEY"] ||= "a" * 64
ENV["KUBO_BLIND_INDEX_KEY"] ||= "b" * 64

require_relative "../config/environment"
# `rails/test_help` es lo que conecta ActiveSupport::TestCase con ActiveRecord
# (fixtures y transacciones por prueba); minitest viene incluido con el.
require "rails/test_help"
