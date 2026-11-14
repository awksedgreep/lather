FROM elixir:1.20-alpine

WORKDIR /app

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY lib lib
COPY config config

RUN mix compile

EXPOSE 4000

CMD ["mix", "run", "-e", "Bandit.start_link(plug: {Lather.Server.EnhancedPlug, [service: MyService]}, port: 4000)"]
