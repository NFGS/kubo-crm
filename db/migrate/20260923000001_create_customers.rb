class CreateCustomers < ActiveRecord::Migration[8.0]
  def change
    create_table :customers, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.string :name, null: false, limit: 160
      t.string :email, limit: 180

      # Datos personales cifrados con AES-256-GCM + indice ciego para busqueda.
      t.string :document_number_encrypted
      t.string :document_number_bidx, limit: 64
      t.string :phone_encrypted
      t.string :phone_bidx, limit: 64

      t.string :city, limit: 120
      t.string :address, limit: 200
      t.string :stage, null: false, default: "LEAD", limit: 20
      t.string :notes, limit: 500
      t.decimal :credit_limit, precision: 14, scale: 2, null: false, default: "0.0"

      # Borrado logico: la historia comercial nunca se destruye.
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :customers, %i[tenant_id stage]
    add_index :customers, :deleted_at
    add_index :customers,
              %i[tenant_id document_number_bidx],
              unique: true,
              where: "document_number_bidx IS NOT NULL AND deleted_at IS NULL",
              name: "idx_customers_tenant_document_unique"

    add_check_constraint :customers,
                         "stage IN ('LEAD', 'PROSPECT', 'CUSTOMER')",
                         name: "customers_stage_check"
    add_check_constraint :customers,
                         "credit_limit >= 0",
                         name: "customers_credit_limit_check"
  end
end
