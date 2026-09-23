source "https://rubygems.org"

gem "rails", "~> 8.0"
gem "pg", "~> 1.5"
gem "puma", "~> 6.4"
gem "bootsnap", require: false

# La gema json 3.x elimino el argumento posicional de JSON.parse, que
# ActiveSupport 8.1 todavia usa internamente. Se fija la serie 2.x para que el
# parseo del cuerpo JSON de las peticiones funcione.
gem "json", "~> 2.9"

group :development, :test do
  gem "debug", require: false
end
