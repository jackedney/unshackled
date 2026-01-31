FROM elixir:1.16-alpine AS build

RUN apk add --no-cache build-base git python3 nodejs npm

WORKDIR /app

COPY mix.exs mix.lock ./
COPY config ./config

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force
RUN mix do deps.get --only $MIX_ENV, deps.compile

COPY assets ./assets
COPY lib ./lib
COPY priv ./priv

RUN mix assets.deploy
RUN mix compile
RUN mix release

FROM alpine:3.19 AS runtime

RUN apk add --no-cache libstdc++ ncurses-libs openssl sqlite-libs

RUN addgroup -S unshackled && adduser -S unshackled -G unshackled

WORKDIR /app

COPY --from=build /app/_build/prod/rel/unshackled ./

RUN mkdir -p /data && chown -R unshackled:unshackled /app /data

USER unshackled

ENV HOME=/home/unshackled

CMD ["./bin/unshackled", "start"]
