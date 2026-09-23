# Los parametros sensibles nunca se escriben en los logs.
Rails.application.config.filter_parameters += [
  :password,
  :token,
  :authorization,
  :secret,
  :document_number,
  :phone,
  :email,
  :credit_limit
]
