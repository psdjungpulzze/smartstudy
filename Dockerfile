# Dockerfile for FunSheep Phoenix application
# Adapted for Google Cloud Run deployment
#
# Build: docker build -t fun_sheep .
# Run:   docker run -p 4000:4000 -e DATABASE_URL=... -e SECRET_KEY_BASE=... fun_sheep

# ============================================================================
# Stage 1: Build
# ============================================================================
ARG ELIXIR_VERSION=1.18.3
ARG OTP_VERSION=27.2.4
ARG DEBIAN_VERSION=bookworm-20250317-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Prepare build dir
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy assets
COPY priv priv
COPY lib lib
COPY assets assets

# Install Node.js for asset build (esbuild/tailwind may need it)
# Phoenix 1.8 uses standalone esbuild/tailwind, so this may not be needed,
# but including for safety with any npm deps in assets/
RUN if [ -f assets/package.json ]; then \
      curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
      apt-get install -y nodejs && \
      cd assets && npm ci; \
    fi

# Copy runtime config before compile so Phoenix.LiveView.Colocated
# hooks (phoenix-colocated/<app>) are generated during mix compile
COPY config/runtime.exs config/

# Compile the application first — this populates _build/prod/phoenix-colocated/fun_sheep/
# which mix assets.deploy's esbuild step depends on
RUN mix compile

# Compile assets after compile so colocated JS hooks resolve
RUN mix assets.deploy

# Build the release
RUN mix release

# ============================================================================
# Stage 2: Runtime
# ============================================================================
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# Set runner ENV
ENV MIX_ENV="prod"

# Copy the release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/fun_sheep ./

USER nobody

# Cloud Run sets PORT env var (default 8080)
ENV PHX_SERVER=true
ENV PORT=8080

# Run pending migrations before booting Phoenix. Ecto.Migrator takes a
# repo-level lock so multiple Cloud Run instances racing here serialize
# safely on cold start.
CMD ["sh", "-c", "bin/fun_sheep eval 'FunSheep.Release.migrate()' && exec bin/fun_sheep start"]
