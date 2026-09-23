Rails.application.routes.draw do
  # Sonda de salud (sin autenticacion).
  get "/api/v1/health", to: "health#show"

  # Rutas estaticas antes del recurso, para que no las capture el parametro :id.
  get "/api/v1/customers/stats", to: "customers#stats"
  get "/api/v1/customers/by-document/:document", to: "customers#by_document"

  resources :customers,
            only: %i[index show create update destroy],
            path: "api/v1/customers"
end
