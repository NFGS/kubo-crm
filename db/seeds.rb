# Semilla opcional del CRM.
#
# Los clientes de demostracion se crean a traves de la API (kubo-infra/scripts/seed.sh),
# porque el `tenant_id` lo genera kubo-iam y este servicio no debe consultar su
# base de datos. Este archivo solo existe para escenarios de prueba aislados.
tenant_id = ENV["KUBO_SEED_TENANT_ID"].presence

if tenant_id.blank?
  puts "[kubo-crm] KUBO_SEED_TENANT_ID no definido: semilla omitida"
else
  customers = [
    { name: "Panaderia El Trigal", email: "compras@eltrigal.co", city: "Armenia", stage: "CUSTOMER" },
    { name: "Ferreteria La 14", email: "contacto@ferreteriala14.co", city: "Calarca", stage: "PROSPECT" }
  ]

  customers.each do |attributes|
    Customer.find_or_create_by!(tenant_id: tenant_id, name: attributes[:name]) do |customer|
      customer.email = attributes[:email]
      customer.city = attributes[:city]
      customer.stage = attributes[:stage]
    end
  end

  puts "[kubo-crm] #{customers.size} clientes de demostracion listos"
end
