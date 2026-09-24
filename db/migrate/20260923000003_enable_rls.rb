# Row Level Security para clientes (P-02).
#
# El aislamiento entre negocios deja de depender de que toda consulta recuerde
# filtrar por tenant_id: lo impone el motor. Cada peticion abre una transaccion y
# fija `app.tenant_id` con set_config(..., true); sin esa variable, la politica no
# devuelve ninguna fila.
#
# `FORCE` es imprescindible: el rol de la aplicacion (kubo_crm) es el dueno de la
# tabla y, sin FORCE, PostgreSQL lo eximiria de las politicas.
class EnableRls < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
      ALTER TABLE customers FORCE ROW LEVEL SECURITY;

      DROP POLICY IF EXISTS customers_tenant_isolation ON customers;
      CREATE POLICY customers_tenant_isolation ON customers
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
        WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);
    SQL
  end

  def down
    execute <<~SQL
      DROP POLICY IF EXISTS customers_tenant_isolation ON customers;
      ALTER TABLE customers NO FORCE ROW LEVEL SECURITY;
      ALTER TABLE customers DISABLE ROW LEVEL SECURITY;
    SQL
  end
end
