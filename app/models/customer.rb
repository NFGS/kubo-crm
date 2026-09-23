# Cliente del negocio (CRM).
#
# Los datos personales sensibles (`document_number`, `phone`) se persisten
# cifrados con AES-256-GCM y se indexan mediante un indice ciego HMAC para poder
# buscar por valor exacto sin descifrar.
class Customer < ApplicationRecord
  STAGES = %w[LEAD PROSPECT CUSTOMER].freeze
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  scope :of_tenant, ->(tenant_id) { where(tenant_id: tenant_id, deleted_at: nil) }
  # Un scope SIEMPRE debe devolver una relacion: si el filtro no aplica se
  # devuelve `all`, nunca nil (encadenar sobre nil rompe la consulta).
  scope :by_stage, ->(stage) { stage.present? ? where(stage: stage) : all }

  validates :name, presence: true, length: { maximum: 160 }
  validates :stage, inclusion: { in: STAGES }
  validates :email, format: { with: EMAIL_FORMAT }, allow_blank: true
  validates :credit_limit, numericality: { greater_than_or_equal_to: 0 }

  def document_number=(value)
    self[:document_number_bidx] = FieldCipher.blind_index(value)
    self[:document_number_encrypted] = FieldCipher.encrypt(value)
  end

  def document_number
    FieldCipher.decrypt(self[:document_number_encrypted])
  end

  def phone=(value)
    self[:phone_bidx] = FieldCipher.blind_index(value)
    self[:phone_encrypted] = FieldCipher.encrypt(value)
  end

  def phone
    FieldCipher.decrypt(self[:phone_encrypted])
  end

  def self.find_by_document(tenant_id, document_number)
    of_tenant(tenant_id).find_by(document_number_bidx: FieldCipher.blind_index(document_number))
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end
end
