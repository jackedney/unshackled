```
 _   _ _   _ ____  _   _    _    ____ _  ___     _____ ____
| | | | \ | / ___|| | | |  / \  / ___| |/ / |   | ____|  _ \
| | | |  \| \___ \| |_| | / _ \| |   | ' /| |   |  _| | | | |
| |_| | |\  |___) |  _  |/ ___ \ |___| . \| |___| |___| |_| |
 \___/|_| \_|____/|_| |_/_/   \_\____|_|\_\_____|_____|____/
```

Zero-context multi-agent reasoning. Agents debate propositions without
path dependence. Each cycle, they get only the current claim, compressed
state, and their role. No memory. No inherited trajectories. Just reasoning.

![Elixir](https://img.shields.io/badge/Elixir-4B275F?style=flat-square&logo=elixir&logoColor=white)
![Phoenix](https://img.shields.io/badge/Phoenix-FD4F00?style=flat-square&logo=phoenixframework&logoColor=white)
![LiveView](https://img.shields.io/badge/LiveView-FD4F00?style=flat-square&logo=phoenixframework&logoColor=white)
![SQLite](https://img.shields.io/badge/SQLite-003B57?style=flat-square&logo=sqlite&logoColor=white)
![Nx](https://img.shields.io/badge/Nx-202020?style=flat-square&logo=elixir&logoColor=white)
![OpenRouter](https://img.shields.io/badge/OpenRouter-6C47FF?style=flat-square&logoColor=white)

`+-------+`<br>
`|  RUN  |`<br>
`+-------+`

```
git clone https://github.com/jackedney/unshackled.git
cd unshackled
cp .env.example .env        # add your OPENROUTER_API_KEY
mix deps.get
mix ecto.create && mix ecto.migrate
mix phx.server              # http://localhost:4000
```

Or with Docker:

```
docker-compose up -d
```

`+----------+`<br>
`|  AGENTS  |`<br>
`+----------+`

```
EVERY CYCLE          Explorer        extends claims by one inferential step
                     Critic          attacks the weakest premise

EVERY 3 CYCLES       Connector       cross-domain analogies
                     Steelman        strongest opposing view
                     Operationalizer falsifiable predictions
                     Quantifier      numerical precision

EVERY 5 CYCLES       Reducer         compresses to essence
                     Boundary Hunter edge cases where claims break
                     Translator      restates in different frameworks
                     Historian       detects re-treading

CONDITIONAL          Grave Keeper    why ideas die (support < 0.4)
                     Cartographer    embedding space nav (stagnation)
                     Perturber       injects frontier ideas (20%/cycle)

ALWAYS               Summarizer      context compression
```

`+----------+`<br>
`|  STATUS  |`<br>
`+----------+`

```
claims born at --------- 0.5
claims die at ----------- 0.2
claims graduate at ------ 0.85
per-cycle decay --------- 0.02
```

`+--------+`<br>
`|  ARCH  |`<br>
`+--------+`

```
Supervisor (one_for_one)
|-- Repo .................. SQLite via Ecto
|-- PubSub ................ real-time event bus
|-- Embedding.ModelServer . transformer model cache
|-- Embedding.Space ....... vector space tracking
|-- Agents.Supervisor ..... DynamicSupervisor for agent tasks
|-- Session ............... session lifecycle manager
|-- Endpoint .............. Phoenix HTTP/WebSocket
|
+-- [per session]
    |-- Cycle.Runner ...... READ -> WRITE -> ARBITER -> PERTURB -> RESET
    +-- Blackboard.Server . shared debate state
```

`+----------+`<br>
`|  CONFIG  |`<br>
`+----------+`

```
OPENROUTER_API_KEY    required    your key from openrouter.ai/keys
DATABASE_PATH         prod only   path to sqlite db
SECRET_KEY_BASE       prod only   mix phx.gen.secret
```

Models rotate randomly per agent per cycle:

```
openai/gpt-5.2
google/gemini-3-pro
moonshot/kimi-k2.5-thinking
anthropic/claude-opus-4.5
zhipu/glm-4.7
deepseek/deepseek-v3.2
mistralai/mistral-large-latest
```

`+--------+`<br>
`|  TEST  |`<br>
`+--------+`

```
mix test              # run tests
mix test --cover      # with coverage
mix format --check-formatted && mix credo --strict && mix dialyzer && mix test
```

`+-----------+`<br>
`|  LICENSE  |`<br>
`+-----------+`

MIT
