Rails.application.routes.draw do
  # Sonda de salud (sin autenticacion).
  get "/api/v1/health", to: "health#show"

  # Debe declararse antes del recurso para que no lo capture el parametro :id.
  get "/api/v1/customers/stats", to: "customers#stats"

  resources :customers,
            only: %i[index show create update destroy],
            path: "api/v1/customers"
end
