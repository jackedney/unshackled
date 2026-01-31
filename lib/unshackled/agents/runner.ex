defmodule Unshackled.Agents.Runner do
  @moduledoc """
  Runner for spawning and executing agents as stateless Tasks.
  Agents receive only current blackboard state and return after completing.

  ## Telemetry Events

  This module emits the following telemetry events:

  * `[:unshackled, :agent, :start]` - Emitted when an agent run starts
    * Measurement: `%{system_time: integer()}` - System time in native time units
    * Metadata: `%{
        agent_role: atom(),
        cycle: non_neg_integer(),
        blackboard_id: pos_integer()
      }`

  * `[:unshackled, :agent, :stop]` - Emitted when an agent run completes successfully
    * Measurement: `%{
        duration: integer(),
        input_tokens: non_neg_integer(),
        output_tokens: non_neg_integer(),
        total_tokens: non_neg_integer()
      }` - All in native time units for duration
    * Metadata: `%{
        agent_role: atom(),
        cycle: non_neg_integer(),
        blackboard_id: pos_integer(),
        model_used: String.t()
      }`

  * `[:unshackled, :agent, :exception]` - Emitted when an agent run encounters an error
    * Measurement: `%{duration: integer()}` - Duration before exception in native time units
    * Metadata: `%{
        agent_role: atom(),
        cycle: non_neg_integer(),
        blackboard_id: pos_integer(),
        kind: atom(),
        reason: term(),
        stacktrace: list()
      }`

  ## Example Usage

  To attach a handler for agent telemetry:

      :telemetry.attach(
        "my-agent-handler",
        [:unshackled, :agent, :stop],
        &MyModule.handle_agent_stop/4,
        nil
      )
  """

  alias Unshackled.Agents.AgentContribution
  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Costs
  alias Unshackled.Costs.Extractor
  alias Unshackled.Costs.LLMCost
  alias Unshackled.LLM.Client
  alias Unshackled.Repo
  alias Unshackled.Blackboard.Server
  alias Unshackled.Session
  alias UnshackledWeb.PubSub
  require Logger

  @doc """
  Spawns an agent as a Task and returns the Task reference.

  The Task receives:
  - Current blackboard state (not history)
  - Role instruction

  The Task:
  - Calls LLM via client.ex with randomly selected model
  - Returns structured result: {role, model_used, output, suggested_delta}
  - Dies after returning (enforced statelessness by Task lifecycle)
  - Logs execution via AgentContribution schema

  ## Parameters

  - agent_module: Module implementing the Agent behaviour
  - blackboard_state: Current Server.t() state
  - blackboard_id: ID for logging purposes
  - cycle_number: Current cycle number for logging
  - session_id: Session ID for cost limit enforcement

  ## Returns

  - A Task reference that can be awaited with Task.await/2

  ## Example

      iex> task = Runner.spawn_agent(ExplorerAgent, state, 1, 5, "session_1")
      iex> {:ok, role, model, output, delta} = Task.await(task, 60000)
  """
  @spec spawn_agent(module(), Server.t(), pos_integer(), non_neg_integer(), String.t() | nil) ::
          Task.t()
  def spawn_agent(
        agent_module,
        blackboard_state,
        blackboard_id,
        cycle_number,
        session_id \\ nil
      )
      when is_atom(agent_module) and is_map(blackboard_state) do
    Task.async(fn ->
      run_agent(agent_module, blackboard_state, blackboard_id, cycle_number, session_id)
    end)
  end

  @doc """
  Runs the agent and returns the result.

  ## Parameters

  - agent_module: Module implementing the Agent behaviour
  - blackboard_state: Current Server.t() state
  - blackboard_id: ID for logging purposes
  - cycle_number: Current cycle number for logging
  - session_id: Session ID for cost limit enforcement

  ## Returns

  - {:ok, role, model_used, output, suggested_delta} on success
  - {:error, reason} on failure

  ## Error Handling

  This function uses `try/rescue` to catch exceptions from:
  1. LLM API calls (Client.chat_random/1) - external HTTP/network calls
  2. Agent response parsing - JSON parsing or validation errors

  The outer `case` handles expected error tuples ({:error, reason})
  from Repo operations and other internal functions.

  Exceptions are caught, logged, emitted as telemetry events,
  and converted to {:error, reason} tuples to maintain consistent API.
  """
  @spec run_agent(module(), Server.t(), pos_integer(), non_neg_integer(), String.t() | nil) ::
          {:ok, atom(), String.t(), map(), float()} | {:error, term()}
  def run_agent(agent_module, blackboard_state, blackboard_id, cycle_number, session_id \\ nil) do
    role = agent_module.role()

    Logger.info(
      metadata: [cycle_number: cycle_number, agent_role: role],
      message: "Agent #{inspect(agent_module)} (role: #{role}) spawned"
    )

    start_time = System.monotonic_time()

    :telemetry.execute(
      [:unshackled, :agent, :start],
      %{system_time: System.system_time()},
      %{
        agent_role: role,
        cycle: cycle_number,
        blackboard_id: blackboard_id
      }
    )

    prompt = agent_module.build_prompt(blackboard_state)

    messages = [
      %{role: "system", content: role_system_instruction(role)},
      %{role: "user", content: prompt}
    ]

    try do
      case Client.chat_random(messages) do
        {:ok, response_struct, model_used} ->
          Logger.info(
            metadata: [cycle_number: cycle_number, agent_role: role],
            message:
              "Agent #{inspect(agent_module)} selected model: #{model_used} (role: #{role})"
          )

          raw_output = agent_module.parse_response(response_struct.content)
          output = normalize_output(raw_output)
          suggested_delta = agent_module.confidence_delta(raw_output)

          log_agent_completion(%{
            agent_module: agent_module,
            blackboard_id: blackboard_id,
            cycle_number: cycle_number,
            role: role,
            model_used: model_used,
            output: output,
            support_delta: suggested_delta,
            accepted: false
          })

          log_agent_execution(%{
            agent_module: agent_module,
            blackboard_id: blackboard_id,
            cycle_number: cycle_number,
            role: role,
            model_used: model_used,
            input_prompt: prompt,
            output_text: response_struct.content,
            support_delta: suggested_delta
          })

          record_llm_cost(%{
            blackboard_id: blackboard_id,
            cycle_number: cycle_number,
            agent_role: role,
            model_used: model_used,
            response_struct: response_struct,
            session_id: session_id
          })

          {:ok, cost_data} = Extractor.extract_cost_data(response_struct)
          duration = System.monotonic_time() - start_time

          :telemetry.execute(
            [:unshackled, :agent, :stop],
            %{
              duration: duration,
              input_tokens: cost_data.input_tokens,
              output_tokens: cost_data.output_tokens,
              total_tokens: cost_data.input_tokens + cost_data.output_tokens
            },
            %{
              agent_role: role,
              cycle: cycle_number,
              blackboard_id: blackboard_id,
              model_used: model_used
            }
          )

          {:ok, role, model_used, output, suggested_delta}

        {:error, reason} ->
          Logger.error(
            metadata: [cycle_number: cycle_number, agent_role: role],
            message: "Agent #{inspect(agent_module)} failed: #{inspect(reason)}"
          )

          duration = System.monotonic_time() - start_time

          :telemetry.execute(
            [:unshackled, :agent, :exception],
            %{duration: duration},
            %{
              agent_role: role,
              cycle: cycle_number,
              blackboard_id: blackboard_id,
              kind: :error,
              reason: reason,
              stacktrace: Process.info(self(), :current_stacktrace)
            }
          )

          {:error, reason}
      end
    rescue
      e in [RuntimeError, ArgumentError] ->
        Logger.error(
          metadata: [cycle_number: cycle_number, agent_role: role],
          message: "Agent #{inspect(agent_module)} crashed: #{Exception.message(e)}"
        )

        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:unshackled, :agent, :exception],
          %{duration: duration},
          %{
            agent_role: role,
            cycle: cycle_number,
            blackboard_id: blackboard_id,
            kind: :exception,
            reason: {e.__struct__, Exception.message(e)},
            stacktrace: __STACKTRACE__
          }
        )

        {:error, {:llm_error, Exception.message(e)}}
    end
  end

  @role_instructions %{
    explorer: "You are an Explorer agent. Extend claims by one inferential step.",
    critic: "You are a Critic agent. Attack the weakest premise of claims.",
    connector: "You are a Connector agent. Find cross-domain analogies.",
    steelman: "You are a Steelman agent. Construct the strongest opposing view.",
    operationalizer:
      "You are an Operationalizer agent. Convert claims to falsifiable predictions.",
    quantifier: "You are a Quantifier agent. Add numerical precision to claims.",
    reducer: "You are a Reducer agent. Compress claims to their fundamental essence.",
    boundary_hunter: "You are a Boundary Hunter agent. Find edge cases where claims break.",
    translator: "You are a Translator agent. Restate claims in different frameworks.",
    historian: "You are a Historian agent. Detect re-treading of previous claims.",
    grave_keeper: "You are a Grave Keeper agent. Track patterns in why ideas die.",
    cartographer: "You are a Cartographer agent. Navigate the embedding space.",
    perturber: "You are a Perturber agent. Inject frontier ideas into the debate."
  }

  @spec role_system_instruction(atom()) :: String.t()
  defp role_system_instruction(role),
    do: Map.get(@role_instructions, role, "You are a test agent.")

  @spec log_agent_completion(map()) :: :ok
  defp log_agent_completion(attrs) do
    output_summary =
      case attrs.output do
        %{new_claim: claim} when is_binary(claim) ->
          String.slice(claim, 0, 60) <> "..."

        %{objection: objection} when is_binary(objection) ->
          String.slice(objection, 0, 60) <> "..."

        %{pivot_claim: pivot} when is_binary(pivot) ->
          String.slice(pivot, 0, 60) <> "..."

        _ ->
          "valid output"
      end

    Logger.debug(
      metadata: [cycle_number: attrs.cycle_number, agent_role: attrs.role],
      message:
        "Agent #{inspect(attrs.agent_module)} completed - delta: #{Float.round(attrs.support_delta, 4)}, output: #{output_summary}"
    )
  end

  @spec log_agent_execution(map()) :: :ok
  defp log_agent_execution(attrs) do
    agent_role_atom = attrs.agent_module.role()

    changeset_attrs = %{
      blackboard_id: attrs.blackboard_id,
      cycle_number: attrs.cycle_number,
      agent_role: Atom.to_string(agent_role_atom),
      model_used: attrs.model_used,
      input_prompt: attrs.input_prompt,
      output_text: attrs.output_text,
      accepted: false,
      support_delta: attrs.support_delta
    }

    changeset = AgentContribution.changeset(%AgentContribution{}, changeset_attrs)

    case Repo.insert(changeset) do
      {:ok, _contribution} -> :ok
      {:error, _changeset} -> :ok
    end
  end

  @spec record_llm_cost(map()) :: :ok
  defp record_llm_cost(attrs) do
    {:ok, cost_data} = Extractor.extract_cost_data(attrs.response_struct)

    cost_attrs = %{
      blackboard_id: attrs.blackboard_id,
      cycle_number: attrs.cycle_number,
      agent_role: Atom.to_string(attrs.agent_role),
      model_used: attrs.model_used,
      input_tokens: cost_data.input_tokens,
      output_tokens: cost_data.output_tokens,
      cost_usd: cost_data.cost_usd
    }

    changeset = LLMCost.changeset(%LLMCost{}, cost_attrs)

    case Repo.insert(changeset) do
      {:ok, llm_cost} ->
        check_cost_limit(attrs.blackboard_id, attrs.session_id)

        if attrs.session_id do
          total_cost = Costs.get_session_total_cost(attrs.blackboard_id)

          PubSub.broadcast_cost_recorded(attrs.session_id, attrs.blackboard_id, %{
            blackboard_id: attrs.blackboard_id,
            total_cost: total_cost,
            latest_cost_entry: %{
              id: llm_cost.id,
              cycle_number: llm_cost.cycle_number,
              agent_role: llm_cost.agent_role,
              model_used: llm_cost.model_used,
              input_tokens: llm_cost.input_tokens,
              output_tokens: llm_cost.output_tokens,
              cost_usd: llm_cost.cost_usd
            }
          })
        end

        :ok

      {:error, changeset} ->
        Logger.warning(
          metadata: [
            cycle_number: attrs.cycle_number,
            agent_role: attrs.agent_role,
            blackboard_id: attrs.blackboard_id
          ],
          message:
            "Failed to record LLM cost: #{inspect(changeset.errors)}. Continuing with agent run."
        )

        :ok
    end
  end

  @spec check_cost_limit(pos_integer(), String.t() | nil) :: :ok
  defp check_cost_limit(blackboard_id, session_id) do
    case Repo.get(BlackboardRecord, blackboard_id) do
      nil ->
        :ok

      %BlackboardRecord{cost_limit_usd: nil} ->
        :ok

      %BlackboardRecord{cost_limit_usd: cost_limit} ->
        total_cost = Costs.get_session_total_cost(blackboard_id)
        cost_limit_float = Decimal.to_float(cost_limit)

        if total_cost > cost_limit_float do
          Logger.info(
            metadata: [
              blackboard_id: blackboard_id,
              total_cost: total_cost,
              cost_limit: cost_limit_float
            ],
            message:
              "Session cost limit exceeded (#{:erlang.float_to_binary(total_cost, decimals: 4)} > #{:erlang.float_to_binary(cost_limit_float, decimals: 4)}). Stopping session."
          )

          if session_id do
            Session.stop(session_id)
          end
        end

        :ok
    end
  end

  # Normalizes agent output to a consistent map format with :valid key.
  # Handles both Ecto schema-based agents (returning {:ok, schema} or {:error, changeset})
  # and legacy agents (returning maps with :valid key).
  @spec normalize_output({:ok, struct()} | {:error, Ecto.Changeset.t()} | map()) :: map()
  defp normalize_output({:ok, schema}) when is_struct(schema) do
    schema
    |> Map.from_struct()
    |> Map.put(:valid, true)
  end

  defp normalize_output({:error, changeset}) when is_struct(changeset, Ecto.Changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    error_string =
      errors
      |> Enum.map(fn {field, messages} -> "#{field}: #{Enum.join(messages, ", ")}" end)
      |> Enum.join("; ")

    %{valid: false, error: error_string}
  end

  defp normalize_output(%{valid: _} = map), do: map

  defp normalize_output(map) when is_map(map) do
    Map.put(map, :valid, false)
  end

  defp normalize_output(_), do: %{valid: false, error: "Unknown output format"}
end
