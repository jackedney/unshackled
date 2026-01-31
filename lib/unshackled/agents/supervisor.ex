defmodule Unshackled.Agents.Supervisor do
  @moduledoc """
  DynamicSupervisor managing agent Tasks for proper supervision and isolation.

  This supervisor spawns agent Tasks dynamically and ensures they are properly
  supervised with :temporary restart strategy (no restart on crash). Failed agents
  log errors but don't crash supervisor.
  """

  use DynamicSupervisor
  alias Unshackled.Agents.Runner
  alias Unshackled.Blackboard.Server

  @doc """
  Starts the AgentSupervisor.
  """
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_children: 100)
  end

  @doc """
  Spawns multiple agents as Tasks under supervisor.

  ## Parameters

  - agent_modules: List of agent module atoms (e.g., [Unshackled.Agents.Explorer, Unshackled.Agents.Critic])
  - blackboard_state: Current Server.t() state
  - blackboard_id: ID for logging purposes
  - cycle_number: Current cycle number for logging
  - session_id: Session ID for cost limit enforcement

  ## Returns

  - {:ok, task_refs} on success, where task_refs is a list of Task references
  - {:error, reason} if spawning fails

  ## Examples

      iex> {:ok, refs} = Supervisor.spawn_agents([Explorer, Critic], state, 1, 1, "session_1")
      iex> length(refs)
      2
  """
  @spec spawn_agents([module()], Server.t(), pos_integer(), non_neg_integer(), String.t() | nil) ::
          {:ok, [Task.t()]} | {:error, term()}
  def spawn_agents(
        agent_modules,
        blackboard_state,
        blackboard_id,
        cycle_number,
        session_id \\ nil
      )
      when is_list(agent_modules) and is_map(blackboard_state) do
    task_refs =
      Enum.map(agent_modules, fn agent_module ->
        spawn_agent_task(agent_module, blackboard_state, blackboard_id, cycle_number, session_id)
      end)

    {:ok, task_refs}
  end

  @doc """
  Awaits all spawned agents and collects their results.

  ## Parameters

  - task_refs: List of Task references from spawn_agents/2
  - timeout_ms: Maximum time to wait for each agent in milliseconds

  ## Returns

  - {:ok, results} where results is a list of {:ok, ...} or {:error, ...} tuples
  - {:error, :timeout} if timeout is exceeded

  ## Examples

      iex> {:ok, refs} = Supervisor.spawn_agents([Explorer, Critic], state, 1, 1)
      iex> {:ok, results} = Supervisor.await_agents(refs, 60000)
      iex> length(results)
      2
  """
  @spec await_agents([Task.t()], non_neg_integer()) :: {:ok, [term()]} | {:error, :timeout}
  def await_agents(task_refs, timeout_ms) when is_list(task_refs) and is_integer(timeout_ms) do
    results =
      Enum.map(task_refs, fn task_ref ->
        await_single_agent(task_ref, timeout_ms)
      end)

    {:ok, results}
  end

  @spec spawn_agent_task(module(), Server.t(), pos_integer(), non_neg_integer(), String.t() | nil) ::
          Task.t()
  defp spawn_agent_task(
         agent_module,
         blackboard_state,
         blackboard_id,
         cycle_number,
         session_id
       )
       when is_atom(agent_module) do
    Task.async(fn ->
      run_agent_under_supervisor(
        agent_module,
        blackboard_state,
        blackboard_id,
        cycle_number,
        session_id
      )
    end)
  end

  @spec run_agent_under_supervisor(
          module(),
          Server.t(),
          pos_integer(),
          non_neg_integer(),
          String.t() | nil
        ) ::
          {:ok, atom(), String.t(), map(), float()} | {:error, term()}
  defp run_agent_under_supervisor(
         agent_module,
         blackboard_state,
         blackboard_id,
         cycle_number,
         session_id
       ) do
    if Code.ensure_loaded?(agent_module) and function_exported?(agent_module, :role, 0) do
      Runner.run_agent(
        agent_module,
        blackboard_state,
        blackboard_id,
        cycle_number,
        session_id
      )
    else
      log_agent_error(agent_module, "Invalid agent module or missing role/0 callback")
      {:error, {:invalid_agent, agent_module}}
    end
  rescue
    error ->
      log_agent_error(agent_module, Exception.message(error))
      {:error, {:agent_crashed, agent_module, Exception.message(error)}}
  end

  @spec await_single_agent(Task.t(), non_neg_integer()) ::
          {:ok, atom(), String.t(), map(), float()} | {:error, term()}
  defp await_single_agent(task_ref, timeout_ms) do
    try do
      Task.await(task_ref, timeout_ms)
    catch
      :exit, {:timeout, {Task, _, [_, timeout]}} ->
        {:error, {:timeout, timeout}}

      :exit, reason ->
        {:error, {:exit, reason}}
    end
  end

  @spec log_agent_error(module(), String.t()) :: :ok
  defp log_agent_error(agent_module, error_message) do
    require Logger
    Logger.error("Agent #{inspect(agent_module)} failed: #{error_message}")
    :ok
  end
end
