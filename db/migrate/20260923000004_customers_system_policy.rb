# Permite a la rotacion de llaves cruzar negocios (P-29, ADR-0019).
#
# La rotacion es una tarea **de sistema**: recorre todos los clientes para
# re-cifrarlos. La politica sigue aislando por negocio en el camino de la
# peticion; la marca `app.system`, que solo fija la propia tarea, abre la tabla
# para el mantenimiento.
class CustomersSystemPolicy < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      DROP POLICY IF EXISTS customers_tenant_isolation ON customers;

      CREATE POLICY customers_tenant_isolation ON customers
        USING (
          tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid
          OR current_setting('app.system', true) = 'on'
        )
        WITH CHECK (
          tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid
          OR current_setting('app.system', true) = 'on'
        );
    SQL
  end

  def down
    execute <<~SQL
      DROP POLICY IF EXISTS customers_tenant_isolation ON customers;

      CREATE POLICY customers_tenant_isolation ON customers
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
        WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);
    SQL
  end
end
