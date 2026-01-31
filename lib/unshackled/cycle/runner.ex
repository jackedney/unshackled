defmodule Unshackled.Cycle.Runner do
  @moduledoc """
  GenServer orchestrating the READ-WRITE-ARBITER-PERTURB-RESET cycle.

  This GenServer manages the complete cycle lifecycle:
  - READ: Get current blackboard state
  - WRITE: Spawn agents for current cycle and await results
  - ARBITER: Apply rules and process agent outputs
  - PERTURB: 20% chance to activate Perturber
  - RESET: Tasks die automatically (stateless by design)

  ## Cycle Modes

  ### :time_based
  - Cycles execute on a fixed schedule (e.g., every 5 minutes)
  - Agents have cycle_duration_ms to complete (default 300000ms = 5 minutes)
  - Partial results from completed agents are still processed
  - Agents that timeout are abandoned

  ### :event_driven
  - Cycles execute as soon as all agents complete or timeout occurs
  - cycle_timeout_ms is the maximum wait time for agent results
  - Progresses immediately when all agents complete

  ## PubSub Events

  This module broadcasts the following events via `UnshackledWeb.PubSub`:

  - `{:cycle_started, cycle_data}` - When a cycle begins execution
  - `{:cycle_complete, cycle_data}` - When a cycle finishes execution

  Subscribe to these events using `UnshackledWeb.PubSub.subscribe_session/1`.
  """

  use GenServer
  require Logger
  import Ecto.Query

  alias Unshackled.Agents.AgentContribution
  alias Unshackled.Agents.Summarizer
  alias Unshackled.Blackboard.Server
  alias Unshackled.Agents.Supervisor
  alias Unshackled.Cycle.Scheduler
  alias Unshackled.Cycle.Arbiter
  alias Unshackled.Embedding.Space
  alias Unshackled.Embedding.Novelty
  alias Unshackled.Evolution.ClaimChangeDetector
  alias Unshackled.GenServer.TerminateHelper
  alias Unshackled.Repo
  alias UnshackledWeb.PubSub, as: WebPubSub

  defstruct [
    :seed_claim,
    :max_cycles,
    :cycle_mode,
    :cycle_timeout_ms,
    :cycle_duration_ms,
    :blackboard_pid,
    :blackboard_id,
    :cycle_count,
    :running,
    :blackboard_name,
    :agent_results,
    :session_id,
    :cost_limit_usd
  ]

  @type t :: %__MODULE__{
          seed_claim: String.t(),
          max_cycles: pos_integer(),
          cycle_mode: atom(),
          cycle_timeout_ms: pos_integer(),
          cycle_duration_ms: pos_integer(),
          blackboard_pid: pid() | nil,
          blackboard_id: pos_integer() | nil,
          cycle_count: non_neg_integer(),
          running: boolean(),
          blackboard_name: atom() | nil,
          agent_results: [term()],
          session_id: String.t() | nil,
          cost_limit_usd: float() | nil
        }

  @doc """
  Starts the CycleRunner with the given configuration.

  ## Options

  - `:seed_claim` - Initial claim to start with (required)
  - `:max_cycles` - Maximum number of cycles to run (required)
  - `:cycle_mode` - Either :time_based or :event_driven (required)
  - `:cycle_timeout_ms` - Timeout for cycle operations (required)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec start_link(keyword(), atom()) :: GenServer.on_start()
  def start_link(opts, name) when is_list(opts) and is_atom(name) do
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    seed_claim = Keyword.fetch!(opts, :seed_claim)
    max_cycles = Keyword.fetch!(opts, :max_cycles)
    cycle_mode = Keyword.fetch!(opts, :cycle_mode)
    cycle_timeout_ms = Keyword.fetch!(opts, :cycle_timeout_ms)
    cycle_duration_ms = Keyword.get(opts, :cycle_duration_ms, 300_000)
    session_id = Keyword.get(opts, :session_id)
    cost_limit_usd = Keyword.get(opts, :cost_limit_usd)

    unless cycle_mode in [:time_based, :event_driven] do
      raise ArgumentError, "cycle_mode must be :time_based or :event_driven"
    end

    state = %__MODULE__{
      seed_claim: seed_claim,
      max_cycles: max_cycles,
      cycle_mode: cycle_mode,
      cycle_timeout_ms: cycle_timeout_ms,
      cycle_duration_ms: cycle_duration_ms,
      blackboard_pid: nil,
      blackboard_id: nil,
      cycle_count: 0,
      running: false,
      blackboard_name: nil,
      agent_results: [],
      session_id: session_id,
      cost_limit_usd: cost_limit_usd
    }

    {:ok, state}
  end

  @doc """
  Starts a new reasoning session with the configured seed claim.

  Returns {:ok, blackboard_id} on success.
  Returns {:error, :already_running} if a session is already active.
  """
  @spec start_session() :: {:ok, pos_integer()} | {:error, :already_running}
  def start_session do
    GenServer.call(__MODULE__, :start_session)
  end

  @spec start_session(atom() | pid()) :: {:ok, pos_integer()} | {:error, :already_running}
  def start_session(server) when is_atom(server) or is_pid(server) do
    GenServer.call(server, :start_session)
  end

  @doc """
  Gets the current cycle count.
  """
  @spec get_cycle_count() :: non_neg_integer()
  def get_cycle_count do
    GenServer.call(__MODULE__, :get_cycle_count)
  end

  @spec get_cycle_count(atom() | pid()) :: non_neg_integer()
  def get_cycle_count(server) when is_atom(server) or is_pid(server) do
    GenServer.call(server, :get_cycle_count)
  end

  @doc """
  Checks if a session is currently running.
  """
  @spec is_running?() :: boolean()
  def is_running? do
    GenServer.call(__MODULE__, :is_running)
  end

  @spec is_running?(atom() | pid()) :: boolean()
  def is_running?(server) when is_atom(server) or is_pid(server) do
    GenServer.call(server, :is_running)
  end

  @impl GenServer
  def handle_call(:start_session, _from, state) do
    if state.running do
      {:reply, {:error, :already_running}, state}
    else
      blackboard_name = :"blackboard_#{System.unique_integer()}"

      opts = if state.cost_limit_usd, do: [cost_limit_usd: state.cost_limit_usd], else: []

      case Server.start_link(state.seed_claim, blackboard_name, opts) do
        {:ok, blackboard_pid} ->
          {:ok, blackboard_id} = Server.persist_state(blackboard_name)

          new_state = %{
            state
            | blackboard_pid: blackboard_pid,
              blackboard_id: blackboard_id,
              cycle_count: 0,
              running: true,
              blackboard_name: blackboard_name,
              agent_results: []
          }

          Server.increment_cycle(blackboard_name)
          updated_state = %{new_state | cycle_count: 1}

          schedule_next_cycle(updated_state)

          {:reply, {:ok, blackboard_id}, updated_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl GenServer
  def handle_call(:get_cycle_count, _from, state) do
    {:reply, state.cycle_count, state}
  end

  @impl GenServer
  def handle_call(:is_running, _from, state) do
    {:reply, state.running, state}
  end

  @impl GenServer
  def handle_info(:run_cycle, state) do
    if state.cycle_count >= state.max_cycles do
      Logger.info("CycleRunner: Reached max_cycles (#{state.max_cycles}), stopping")

      new_state = %{state | running: false}

      {:noreply, new_state}
    else
      execute_cycle(state)
    end
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.error("Blackboard process exited with reason: #{inspect(reason)}")

    new_state = %{
      state
      | running: false,
        blackboard_pid: nil
    }

    {:noreply, new_state}
  end

  @doc """
  Handles GenServer termination and cleanup.

  Logs the shutdown reason along with the current cycle count for debugging
  and operational visibility.
  """
  @impl GenServer
  @spec terminate(term(), t()) :: :ok
  def terminate(reason, state) do
    TerminateHelper.log_shutdown("Cycle.Runner", reason, state.cycle_count)
  end

  @spec execute_cycle(t()) :: {:noreply, t()} | {:stop, :normal, t()}
  defp execute_cycle(state) do
    cycle_start_time = System.monotonic_time(:millisecond)

    Logger.info(
      metadata: [cycle_number: state.cycle_count],
      message: "Cycle #{state.cycle_count} started"
    )

    # Broadcast cycle started if session_id is available
    if state.session_id do
      WebPubSub.broadcast_cycle_started(state.session_id, %{
        session_id: state.session_id,
        cycle_number: state.cycle_count,
        blackboard_id: state.blackboard_id
      })
    end

    with {:ok, _} <- read_phase(state),
         {:ok, _} <- resurrection_phase(state, :pre_cycle),
         {:ok, agent_data} <- write_phase(state),
         {:ok, _} <- arbiter_phase(state, agent_data.results),
         {:ok, _} <- novelty_bonus_phase(state),
         {:ok, _} <- decay_phase(state),
         {:ok, _} <- resurrection_phase(state, :post_decay),
         {:ok, _} <- perturb_phase(state),
         {:ok, _} <- reset_phase(state) do
      cycle_end_time = System.monotonic_time(:millisecond)
      duration_ms = cycle_end_time - cycle_start_time

      Logger.info(
        metadata: [cycle_number: state.cycle_count],
        message: "Cycle #{state.cycle_count} completed in #{duration_ms}ms"
      )

      new_cycle_count = state.cycle_count + 1

      Server.increment_cycle(state.blackboard_name)

      # Get current blackboard state for broadcast
      blackboard_state = Server.get_state(state.blackboard_name)

      # Broadcast cycle complete if session_id is available
      if state.session_id do
        WebPubSub.broadcast_cycle_complete(state.session_id, %{
          session_id: state.session_id,
          cycle_number: state.cycle_count,
          blackboard_id: state.blackboard_id,
          duration_ms: duration_ms,
          support_strength: blackboard_state.support_strength,
          current_claim: truncate_claim(blackboard_state.current_claim)
        })
      end

      new_state = %{state | cycle_count: new_cycle_count, agent_results: agent_data.results}

      if new_cycle_count > state.max_cycles do
        Logger.info("CycleRunner: Completed all #{state.max_cycles} cycles")

        # Broadcast session completed
        if state.session_id do
          WebPubSub.broadcast_session_completed(state.session_id)
        end

        {:noreply, %{new_state | running: false}}
      else
        schedule_next_cycle(new_state)
        {:noreply, new_state}
      end
    else
      {:error, reason} ->
        Logger.error(
          metadata: [cycle_number: state.cycle_count],
          message: "Cycle #{state.cycle_count} failed: #{inspect(reason)}"
        )

        new_state = %{state | running: false}
        {:noreply, new_state}
    end
  end

  @spec read_phase(t()) :: {:ok, atom()}
  defp read_phase(state) do
    Logger.debug(
      metadata: [cycle_number: state.cycle_count],
      message: "READ phase complete"
    )

    {:ok, :read_complete}
  end

  @spec write_phase(t()) :: {:ok, map()} | {:error, term()}
  defp write_phase(state) do
    Logger.debug(
      metadata: [cycle_number: state.cycle_count],
      message: "WRITE phase - spawning agents"
    )

    blackboard_state = Server.get_state(state.blackboard_name)

    # Safety check: if claim is nil, skip agent spawning
    if blackboard_state.current_claim == nil do
      Logger.warning(
        metadata: [cycle_number: state.cycle_count],
        message: "WRITE phase skipped - no active claim (resurrection failed or not possible)"
      )

      {:ok, %{results: [], timeouts: 0}}
    else
      agent_modules = select_agents_for_cycle(state.cycle_count, blackboard_state)

      case agent_modules do
        [] when state.cycle_mode == :event_driven ->
          Logger.error(
            metadata: [cycle_number: state.cycle_count],
            message: "Event-driven mode requires at least one agent to be spawned"
          )

          {:error, :no_agents_spawned}

        [] ->
          Logger.debug(
            metadata: [cycle_number: state.cycle_count],
            message: "No agents to spawn this cycle"
          )

          {:ok, %{results: [], timeouts: 0}}

        modules ->
          await_agent_results(state, modules, blackboard_state)
      end
    end
  end

  @spec await_agent_results(t(), [module()], Unshackled.Blackboard.Server.t()) :: {:ok, map()}
  defp await_agent_results(state, modules, blackboard_state) do
    {:ok, task_refs} =
      Supervisor.spawn_agents(
        modules,
        blackboard_state,
        state.blackboard_id,
        state.cycle_count,
        state.session_id
      )

    timeout_ms = determine_timeout(state)
    {:ok, results} = Supervisor.await_agents(task_refs, timeout_ms)

    process_agent_results(state, results, modules)
  end

  @spec determine_timeout(t()) :: pos_integer()
  defp determine_timeout(state) do
    case state.cycle_mode do
      :time_based -> state.cycle_duration_ms
      :event_driven -> state.cycle_timeout_ms
    end
  end

  @spec process_agent_results(t(), [term()], [module()]) :: {:ok, map()}
  defp process_agent_results(state, results, modules) do
    completed_results =
      Enum.filter(results, fn result -> match?({:ok, _, _, _, _}, result) end)

    timeout_results =
      Enum.filter(results, fn result -> match?({:error, {:timeout, _}}, result) end)

    error_results = Enum.filter(results, fn result -> match?({:error, _}, result) end)

    completed_count = length(completed_results)
    timeout_count = length(timeout_results)
    error_count = length(error_results)
    total_count = length(modules)

    log_agent_completion(
      completed_count,
      timeout_count,
      error_count,
      total_count,
      state.cycle_count
    )

    check_empty_cycle(completed_count, timeout_count, error_count, total_count, state.cycle_count)

    {:ok, %{results: completed_results, timeouts: timeout_count}}
  end

  @spec log_agent_completion(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok
  defp log_agent_completion(completed, timeouts, errors, total, cycle_number) do
    Logger.debug(
      metadata: [cycle_number: cycle_number],
      message:
        "Agents completed - #{completed}/#{total} successful, #{timeouts} timeouts, #{errors} errors"
    )
  end

  @spec check_empty_cycle(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok
  defp check_empty_cycle(_completed_count, timeout_count, error_count, total_count, cycle_number) do
    if timeout_count + error_count >= total_count do
      Logger.warning(
        metadata: [cycle_number: cycle_number],
        message: "All agents failed or timed out - empty cycle"
      )
    end
  end

  @spec arbiter_phase(t(), [term()]) :: {:ok, atom()} | {:error, term()}
  defp arbiter_phase(state, agent_results) do
    Logger.debug(
      metadata: [cycle_number: state.cycle_count],
      message: "ARBITER phase - applying rules to #{length(agent_results)} results"
    )

    blackboard_state = Server.get_state(state.blackboard_name)

    case Arbiter.evaluate(agent_results, blackboard_state) do
      {:ok, accepted} ->
        accepted_count = length(accepted)

        Logger.debug(
          metadata: [cycle_number: state.cycle_count],
          message: "Accepted #{accepted_count} agent contributions"
        )

        apply_accepted_contributions(state, accepted)

        {:ok, :arbiter_complete}

      _error ->
        Logger.error(
          metadata: [cycle_number: state.cycle_count],
          message: "Arbiter evaluation failed"
        )

        {:error, {:arbiter_failed, :evaluation_error}}
    end
  end

  @spec apply_accepted_contributions(t(), [map()]) :: :ok
  defp apply_accepted_contributions(state, accepted) do
    blackboard_name = state.blackboard_name

    Enum.each(accepted, fn contribution ->
      role = contribution.role
      output = contribution.output
      delta = contribution.confidence_delta

      # Mark this contribution as accepted in the database
      mark_contribution_accepted(state.blackboard_id, state.cycle_count, role)

      cond do
        role == :explorer and Map.get(output, :new_claim) ->
          new_claim = Map.get(output, :new_claim)

          Logger.debug(
            metadata: [cycle_number: state.cycle_count, agent_role: :explorer],
            message: "Explorer accepted - updating claim: #{String.slice(new_claim, 0, 60)}"
          )

          Server.update_claim(blackboard_name, new_claim)

        role == :critic and Map.get(output, :objection) ->
          objection = Map.get(output, :objection)

          Logger.debug(
            metadata: [cycle_number: state.cycle_count, agent_role: :critic],
            message: "Critic accepted - setting active objection"
          )

          Server.set_active_objection(blackboard_name, objection)

        role == :connector and Map.get(output, :analogy) ->
          analogy = Map.get(output, :analogy)

          Logger.debug(
            metadata: [cycle_number: state.cycle_count, agent_role: :connector],
            message: "Connector accepted - setting analogy of record"
          )

          Server.set_analogy(blackboard_name, analogy)

        delta != 0 ->
          Logger.debug(
            metadata: [cycle_number: state.cycle_count, agent_role: role],
            message: "Applying confidence delta #{Float.round(delta, 4)} from #{role}"
          )

          Server.update_support(blackboard_name, delta)

        true ->
          :ok
      end
    end)

    :ok
  end

  @spec mark_contribution_accepted(pos_integer(), non_neg_integer(), atom()) :: :ok
  defp mark_contribution_accepted(blackboard_id, cycle_number, role) do
    role_string = Atom.to_string(role)

    from(c in AgentContribution,
      where:
        c.blackboard_id == ^blackboard_id and
          c.cycle_number == ^cycle_number and
          c.agent_role == ^role_string
    )
    |> Repo.update_all(set: [accepted: true])

    :ok
  end

  @spec novelty_bonus_phase(t()) :: {:ok, atom()}
  defp novelty_bonus_phase(state) do
    Logger.debug(
      metadata: [cycle_number: state.cycle_count],
      message: "NOVELTY BONUS phase - calculating novelty"
    )

    blackboard_state = Server.get_state(state.blackboard_name)

    space_pid = Process.whereis(Space)

    if is_pid(space_pid) and Process.alive?(space_pid) and state.blackboard_id do
      with {:ok, trajectory} <- Space.get_trajectory(state.blackboard_id),
           {:ok, claim_embedding} <- Space.embed_claim(blackboard_state.current_claim),
           {:ok, novelty_score} <- Novelty.calculate_novelty(claim_embedding, trajectory),
           {:ok, boosted} <-
             Novelty.apply_novelty_bonus(novelty_score, blackboard_state.support_strength) do
        delta = boosted - blackboard_state.support_strength

        if delta > 0 do
          Logger.debug(
            metadata: [cycle_number: state.cycle_count],
            message:
              "Applying novelty bonus +#{Float.round(delta, 4)} (novelty: #{Float.round(novelty_score, 4)})"
          )

          Server.update_support(state.blackboard_name, delta)
        else
          Logger.debug(
            metadata: [cycle_number: state.cycle_count],
            message: "No novelty bonus applied (novelty: #{Float.round(novelty_score, 4)})"
          )
        end

        {:ok, :novelty_bonus_applied}
      else
        _ ->
          Logger.debug(
            metadata: [cycle_number: state.cycle_count],
            message: "Novelty bonus skipped - unable to calculate"
          )

          {:ok, :novelty_bonus_skipped}
      end
    else
      Logger.debug(
        metadata: [cycle_number: state.cycle_count],
        message: "Novelty bonus skipped - EmbeddingSpace not available or no blackboard_id"
      )

      {:ok, :novelty_bonus_skipped}
    end
  end

  @spec perturb_phase(t()) :: {:ok, atom()}
  defp perturb_phase(state) do
    Logger.debug(
      metadata: [cycle_number: state.cycle_count],
      message: "PERTURB phase - checking activation"
    )

    perturb_roll = :rand.uniform()

    if perturb_roll <= 0.2 do
      Logger.debug(
        metadata: [cycle_number: state.cycle_count],
        message: "Perturber activated (roll: #{Float.round(perturb_roll, 4)})"
      )

      eligible_frontiers = Server.get_eligible_frontiers(state.blackboard_name)

      if length(eligible_frontiers) > 0 do
        Logger.debug(
          metadata: [cycle_number: state.cycle_count],
          message: "Found #{length(eligible_frontiers)} eligible frontiers"
        )

        {:ok, :perturber_activated}
      else
        Logger.debug(
          metadata: [cycle_number: state.cycle_count],
          message: "No eligible frontiers, skipping Perturber"
        )

        {:ok, :perturber_skipped}
      end
    else
      Logger.debug(
        metadata: [cycle_number: state.cycle_count],
        message: "Perturber not activated (roll: #{Float.round(perturb_roll, 4)})"
      )

      {:ok, :perturber_not_activated}
    end
  end

  @spec decay_phase(t()) :: {:ok, atom()}
  defp decay_phase(state) do
    Logger.debug(
      metadata: [cycle_number: state.cycle_count],
      message: "DECAY phase - applying per-cycle decay"
    )

    # Use < 1 instead of == 0 to avoid dialyzer warning about pos_integer comparison
    # This is defensive coding - cycle_count should always be >= 1 when this is called
    if state.cycle_count < 1 do
      Logger.debug(
        metadata: [cycle_number: state.cycle_count],
        message: "Decay skipped on cycle 0 (no decay before first cycle)"
      )

      {:ok, :decay_skipped}
    else
      blackboard_state = Server.get_state(state.blackboard_name)
      current_support = blackboard_state.support_strength

      decay_amount = -0.02
      decayed_support = current_support + decay_amount

      final_support =
        if decayed_support < 0.2 do
          0.2
        else
          decayed_support
        end

      if final_support < current_support do
        Logger.info(
          metadata: [cycle_number: state.cycle_count],
          message:
            "Decay applied -#{Float.round(abs(decay_amount), 4)} (#{Float.round(current_support, 4)} -> #{Float.round(final_support, 4)})"
        )

        Server.update_support(state.blackboard_name, final_support - current_support)
      else
        Logger.debug(
          metadata: [cycle_number: state.cycle_count],
          message: "Decay would bring support below floor (0.2), clamped to 0.2"
        )
      end

      {:ok, :decay_applied}
    end
  end

  # Unified resurrection phase that handles both pre-cycle and post-decay scenarios.
  # - :pre_cycle - Runs early in the cycle to ensure we have a valid claim before agents spawn
  # - :post_decay - Runs after decay to catch claims that just died this cycle
  @spec resurrection_phase(t(), :pre_cycle | :post_decay) ::
          {:ok, atom()} | {:error, :no_frontiers_available}
  defp resurrection_phase(state, context) do
    blackboard_state = Server.get_state(state.blackboard_name)

    if blackboard_state.current_claim == nil do
      {log_message, success_result, failure_message} = resurrection_context(context)

      Logger.info(
        metadata: [cycle_number: state.cycle_count],
        message: log_message
      )

      case attempt_resurrection(state, blackboard_state) do
        {:ok, :resurrected} ->
          {:ok, success_result}

        {:error, :no_frontiers_available} ->
          Logger.info(
            metadata: [cycle_number: state.cycle_count],
            message: failure_message
          )

          {:error, :no_frontiers_available}
      end
    else
      {:ok, alive_result(context)}
    end
  end

  @spec resurrection_context(:pre_cycle | :post_decay) :: {String.t(), atom(), String.t()}
  defp resurrection_context(:pre_cycle) do
    {
      "Claim is nil - attempting resurrection from frontier pool",
      :resurrected,
      "Session ending - no active claim and no frontiers for resurrection"
    }
  end

  defp resurrection_context(:post_decay) do
    {
      "Claim died this cycle - attempting immediate resurrection",
      :resurrection_after_decay,
      "Session ending - claim died and no frontiers for resurrection"
    }
  end

  @spec alive_result(:pre_cycle | :post_decay) :: atom()
  defp alive_result(:pre_cycle), do: :claim_alive
  defp alive_result(:post_decay), do: :claim_survived_decay

  @spec attempt_resurrection(t(), Server.t()) ::
          {:ok, :resurrected} | {:error, :no_frontiers_available}
  defp attempt_resurrection(state, blackboard_state) do
    # First try to get eligible frontiers (2+ sponsors, not activated)
    eligible_frontiers = Server.get_eligible_frontiers(state.blackboard_name)

    if length(eligible_frontiers) > 0 do
      # Select the best frontier (highest sponsor count, or use weighted selection)
      selected = Server.select_weighted_frontier(state.blackboard_name)

      if selected do
        new_claim = selected.idea_text
        idea_id = selected.id

        Logger.info(
          metadata: [cycle_number: state.cycle_count],
          message:
            "Resurrecting claim from frontier pool: #{String.slice(new_claim, 0, 60)}... (#{selected.sponsor_count} sponsors)"
        )

        # Mark the frontier as activated
        Server.activate_frontier(state.blackboard_name, idea_id)

        # Update the claim
        Server.update_claim(state.blackboard_name, new_claim)

        # Reset support to a moderate level for the new claim
        current_support = blackboard_state.support_strength
        new_support = 0.5
        delta = new_support - current_support
        Server.update_support(state.blackboard_name, delta)

        Logger.info(
          metadata: [cycle_number: state.cycle_count],
          message: "Resurrection complete - new claim support reset to 0.5"
        )

        {:ok, :resurrected}
      else
        # No weighted frontier selected, try first eligible
        first = hd(eligible_frontiers)
        new_claim = first.idea_text
        idea_id = first.id

        Logger.info(
          metadata: [cycle_number: state.cycle_count],
          message:
            "Resurrecting claim from first eligible frontier: #{String.slice(new_claim, 0, 60)}..."
        )

        Server.activate_frontier(state.blackboard_name, idea_id)
        Server.update_claim(state.blackboard_name, new_claim)

        current_support = blackboard_state.support_strength
        delta = 0.5 - current_support
        Server.update_support(state.blackboard_name, delta)

        {:ok, :resurrected}
      end
    else
      # No eligible frontiers - check if there are any frontiers at all
      all_frontiers = blackboard_state.frontier_pool || %{}

      if map_size(all_frontiers) > 0 do
        # There are frontiers but none are eligible (< 2 sponsors)
        # Find the one with most sponsors
        best_frontier =
          all_frontiers
          |> Enum.filter(fn {_id, idea} -> not Map.get(idea, :activated, false) end)
          |> Enum.max_by(fn {_id, idea} -> Map.get(idea, :sponsor_count, 0) end, fn -> nil end)

        case best_frontier do
          {id, idea} ->
            new_claim = idea.idea_text

            Logger.info(
              metadata: [cycle_number: state.cycle_count],
              message:
                "Resurrecting from best available frontier (#{idea.sponsor_count} sponsor): #{String.slice(new_claim, 0, 60)}..."
            )

            Server.activate_frontier(state.blackboard_name, id)
            Server.update_claim(state.blackboard_name, new_claim)

            current_support = blackboard_state.support_strength
            delta = 0.4 - current_support
            Server.update_support(state.blackboard_name, delta)

            {:ok, :resurrected}

          nil ->
            Logger.warning(
              metadata: [cycle_number: state.cycle_count],
              message: "No unactivated frontiers available for resurrection"
            )

            {:error, :no_frontiers_available}
        end
      else
        Logger.warning(
          metadata: [cycle_number: state.cycle_count],
          message: "Frontier pool is empty - no resurrection possible"
        )

        {:error, :no_frontiers_available}
      end
    end
  end

  @spec reset_phase(t()) :: {:ok, atom()}
  defp reset_phase(state) do
    Logger.debug(
      metadata: [cycle_number: state.cycle_count],
      message: "RESET phase - agents died as Tasks"
    )

    # Persist blackboard state including updated cycle_count
    Server.persist_state(state.blackboard_name)

    # Store trajectory point for this cycle
    store_trajectory_point(state)

    # Check for claim changes and record transitions
    check_and_record(state)

    # Create snapshot for historical analysis
    Server.create_snapshot(state.blackboard_name)

    # Trigger summarizer unconditionally after every cycle
    trigger_summarizer(state)

    {:ok, :reset_complete}
  end

  @spec check_and_record(t()) :: :ok
  defp check_and_record(state) do
    if state.cycle_count > 1 do
      blackboard_id = state.blackboard_id
      current_cycle = state.cycle_count

      case ClaimChangeDetector.detect_changes(blackboard_id) do
        {:ok, transitions} ->
          most_recent_transition = Enum.find(transitions, fn t -> t.to_cycle == current_cycle end)

          if most_recent_transition do
            Logger.debug(
              metadata: [cycle_number: current_cycle],
              message: "Claim change detected and recorded"
            )

            broadcast_claim_changed_if_session_available(state, most_recent_transition)
          else
            Logger.debug(
              metadata: [cycle_number: current_cycle],
              message: "No claim change detected"
            )
          end

        {:error, reason} ->
          Logger.warning(
            metadata: [cycle_number: current_cycle],
            message: "Failed to detect claim changes: #{inspect(reason)}"
          )
      end
    end

    :ok
  end

  @spec broadcast_claim_changed_if_session_available(t(), map()) :: :ok
  defp broadcast_claim_changed_if_session_available(state, transition) do
    if state.session_id do
      transition_map = %{
        blackboard_id: transition.blackboard_id,
        from_cycle: transition.from_cycle,
        to_cycle: transition.to_cycle,
        previous_claim: transition.previous_claim,
        new_claim: transition.new_claim,
        trigger_agent: transition.trigger_agent,
        trigger_contribution_id: transition.trigger_contribution_id,
        change_type: transition.change_type,
        diff_additions: transition.diff_additions,
        diff_removals: transition.diff_removals
      }

      WebPubSub.broadcast_claim_changed(state.session_id, transition_map)
    end

    :ok
  end

  @spec trigger_summarizer(t()) :: :ok
  defp trigger_summarizer(state) do
    blackboard_id = state.blackboard_id
    current_cycle = state.cycle_count

    Logger.debug(
      metadata: [cycle_number: current_cycle],
      message: "Triggering summarizer for cycle #{current_cycle}"
    )

    Task.start(fn -> trigger_summarizer_async(blackboard_id) end)

    :ok
  end

  @spec trigger_summarizer_async(pos_integer()) :: :ok
  defp trigger_summarizer_async(blackboard_id) do
    case Summarizer.summarize(blackboard_id) do
      {:ok, _summary} ->
        Logger.info(
          metadata: [blackboard_id: blackboard_id],
          message: "Summary generated successfully"
        )

      {:error, reason} ->
        Logger.warning(
          metadata: [blackboard_id: blackboard_id],
          message: "Failed to generate summary: #{inspect(reason)}"
        )
    end

    :ok
  end

  @spec store_trajectory_point(t()) :: :ok
  defp store_trajectory_point(state) do
    blackboard_state = Server.get_state(state.blackboard_name)
    space_pid = Process.whereis(Space)

    if is_pid(space_pid) and Process.alive?(space_pid) and state.blackboard_id do
      case Space.embed_claim(blackboard_state.current_claim) do
        {:ok, embedding} ->
          point = %{
            blackboard_id: state.blackboard_id,
            cycle_number: state.cycle_count,
            embedding_vector: embedding,
            claim_text: blackboard_state.current_claim,
            support_strength: blackboard_state.support_strength
          }

          case Space.store_trajectory_point(point) do
            {:ok, _} ->
              Logger.debug(
                metadata: [cycle_number: state.cycle_count],
                message: "Trajectory point stored for cycle #{state.cycle_count}"
              )

            {:error, _reason} ->
              Logger.warning(
                metadata: [cycle_number: state.cycle_count],
                message: "Failed to store trajectory point for cycle #{state.cycle_count}"
              )
          end

        {:error, _reason} ->
          Logger.debug(
            metadata: [cycle_number: state.cycle_count],
            message: "Could not embed claim for trajectory point"
          )
      end
    else
      Logger.debug(
        metadata: [cycle_number: state.cycle_count],
        message: "EmbeddingSpace not available for trajectory storage"
      )
    end

    :ok
  end

  @spec select_agents_for_cycle(non_neg_integer(), Unshackled.Blackboard.Server.t()) :: [module()]
  defp select_agents_for_cycle(cycle_count, blackboard_state) do
    Scheduler.agents_for_cycle(cycle_count, blackboard_state)
  end

  @spec schedule_next_cycle(t()) :: :ok
  defp schedule_next_cycle(state) do
    case state.cycle_mode do
      :time_based ->
        Process.send_after(self(), :run_cycle, state.cycle_timeout_ms)

      :event_driven ->
        send(self(), :run_cycle)
    end

    :ok
  end

  @spec truncate_claim(String.t() | nil) :: String.t() | nil
  defp truncate_claim(nil), do: nil

  defp truncate_claim(claim) when is_binary(claim) do
    if String.length(claim) > 200 do
      String.slice(claim, 0, 200) <> "..."
    else
      claim
    end
  end
end
