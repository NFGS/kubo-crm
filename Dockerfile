# syntax=docker/dockerfile:1.7

# ---------- Etapa 1: dependencias ----------
FROM ruby:3.4-slim AS build

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends build-essential libpq-dev git \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

COPY . .

# ---------- Etapa 2: ejecucion ----------
FROM ruby:3.4-slim AS runtime

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends libpq5 wget \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -u 1000 kubo

WORKDIR /app

ENV RAILS_ENV=production \
    BUNDLE_WITHOUT=development:test \
    RAILS_LOG_TO_STDOUT=1

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

RUN chmod +x bin/docker-entrypoint bin/rails bin/rake \
 && mkdir -p tmp/pids log \
 && chown -R kubo:kubo /app

USER kubo
EXPOSE 8082

HEALTHCHECK --interval=15s --timeout=5s --start-period=45s --retries=5 \
  CMD wget -qO- http://localhost:8082/api/v1/health || exit 1

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
