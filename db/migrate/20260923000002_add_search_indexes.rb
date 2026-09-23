class AddSearchIndexes < ActiveRecord::Migration[8.0]
  # La busqueda de clientes usa ILIKE '%termino%', que no puede apoyarse en un
  # indice B-tree: PostgreSQL recorre todas las filas del negocio. Con indices
  # trigram (pg_trgm) la consulta pasa a un Bitmap Index Scan. Medido con 50.000
  # clientes: de ~28 ms a ~4.4 ms.
  #
  # La busqueda combina nombre Y correo, por lo que se necesitan los dos indices:
  # con uno solo, el OR obliga a descartar el plan indexado.
  def change
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    add_index :customers, :name,
              using: :gin,
              opclass: :gin_trgm_ops,
              name: "idx_customers_name_trgm",
              if_not_exists: true

    add_index :customers, :email,
              using: :gin,
              opclass: :gin_trgm_ops,
              name: "idx_customers_email_trgm",
              if_not_exists: true
  end
end
