namespace :kubo do
  desc "Rota los campos cifrados a la llave actual del anillo (P-29)"
  task rotate_field_keys: :environment do
    resumen = FieldKeyRotation.call
    puts "[kubo] rotacion: #{resumen[:rotated]} fila(s) rotada(s), " \
         "#{resumen[:unreadable]} valor(es) ilegible(s)"
  end
end
