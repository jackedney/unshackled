defmodule Unshackled.Cycle.Scheduler do
  @moduledoc """
  Agent activation scheduler for cycle-based reasoning.

  This module determines which agents should be activated for each cycle
  based on cycle count, blackboard state, and system conditions.

  ## Agent Activation Rules

  - Core agents (Explorer, Critic): every cycle
  - Analytical agents (Connector, Steelman, Operationalizer, Quantifier): every 3 cycles
  - Structural agents (Reducer, Boundary Hunter, Translator): every 5 cycles
  - Historian: every 5 cycles
  - Grave Keeper: when support_strength < 0.4
  - Cartographer: when stagnation detected
  - Perturber: 20% probability each cycle (if eligible frontiers exist)

  """

  alias Unshackled.Blackboard.Server
  alias Unshackled.Embedding.Stagnation
  alias Unshackled.Embedding.Space
  alias Unshackled.Agents.Explorer
  alias Unshackled.Agents.Critic
  alias Unshackled.Agents.Connector
  alias Unshackled.Agents.Steelman
  alias Unshackled.Agents.Operationalizer
  alias Unshackled.Agents.Quantifier
  alias Unshackled.Agents.Reducer
  alias Unshackled.Agents.BoundaryHunter
  alias Unshackled.Agents.Translator
  alias Unshackled.Agents.Historian
  alias Unshackled.Agents.GraveKeeper
  alias Unshackled.Agents.Cartographer
  alias Unshackled.Agents.Perturber

  @type agent_result :: {atom(), map()} | {:error, any()}
  @type cycle_state :: %{blackboard_id: pos_integer(), cycle_count: non_neg_integer()}

  # Data-driven agent schedule configuration
  # Format: {agents, schedule} where schedule is:
  #   :every_cycle - runs every cycle
  #   {:every, n} - runs every n cycles (when rem(cycle_count, n) == 0)
  @agent_schedule [
    {[Explorer, Critic], :every_cycle},
    {[Connector, Steelman, Operationalizer, Quantifier], {:every, 3}},
    {[Reducer, BoundaryHunter, Translator], {:every, 5}},
    {[Historian], {:every, 5}}
  ]

  @doc """
  Returns list of agent modules to activate for the current cycle.

  ## Parameters

  - cycle_count: Current cycle number
  - blackboard_state: Current blackboard state map

  ## Returns

  - List of agent modules to spawn
  """
  @spec agents_for_cycle(non_neg_integer(), Server.t()) :: [module()]
  def agents_for_cycle(0, _blackboard_state) do
    raise ArgumentError, "Cycle count must be at least 1, got 0"
  end

  def agents_for_cycle(cycle_count, blackboard_state)
      when is_integer(cycle_count) and cycle_count >= 1 do
    scheduled_agents(cycle_count)
    |> add_conditional_agents(cycle_count, blackboard_state)
    |> Enum.uniq()
  end

  # Collects agents based on the data-driven schedule configuration
  @spec scheduled_agents(non_neg_integer()) :: [module()]
  defp scheduled_agents(cycle_count) do
    Enum.flat_map(@agent_schedule, fn
      {agents, :every_cycle} -> agents
      {agents, {:every, n}} when rem(cycle_count, n) == 0 -> agents
      _ -> []
    end)
  end

  # Adds agents that depend on runtime conditions (state, stagnation, probability)
  @spec add_conditional_agents([module()], non_neg_integer(), Server.t()) :: [module()]
  defp add_conditional_agents(agents, cycle_count, blackboard_state) do
    agents
    |> maybe_add_grave_keeper(blackboard_state)
    |> maybe_add_cartographer(cycle_count, blackboard_state)
    |> maybe_add_perturber()
  end

  @spec maybe_add_grave_keeper([module()], Server.t()) :: [module()]
  defp maybe_add_grave_keeper(agents, %Server{support_strength: support}) when support < 0.4 do
    [GraveKeeper | agents]
  end

  defp maybe_add_grave_keeper(agents, _), do: agents

  @spec maybe_add_cartographer([module()], non_neg_integer(), Server.t()) :: [module()]
  defp maybe_add_cartographer(agents, cycle_count, %Server{blackboard_id: blackboard_id})
       when is_integer(blackboard_id) and cycle_count >= 5 do
    case check_stagnation(blackboard_id, cycle_count) do
      {true, _cycles, _avg} -> [Cartographer | agents]
      {false, _, _} -> agents
    end
  end

  defp maybe_add_cartographer(agents, _, _), do: agents

  @spec check_stagnation(pos_integer(), non_neg_integer()) ::
          {boolean(), non_neg_integer(), float()}
  defp check_stagnation(blackboard_id, current_cycle) do
    from_cycle = max(0, current_cycle - 10)
    space_pid = Process.whereis(Unshackled.Embedding.Space)

    if is_pid(space_pid) and Process.alive?(space_pid) do
      try do
        case Space.get_trajectory(blackboard_id) do
          {:ok, trajectory_points} ->
            recent_points =
              trajectory_points
              |> Enum.filter(&(&1.cycle_number >= from_cycle and &1.cycle_number <= current_cycle))
              |> Enum.sort_by(& &1.cycle_number)

            Stagnation.detect_stagnation(recent_points, 0.01)

          _ ->
            {false, 0, 0.0}
        end
      catch
        :exit, _ -> {false, 0, 0.0}
      end
    else
      {false, 0, 0.0}
    end
  end

  @spec maybe_add_perturber([module()]) :: [module()]
  defp maybe_add_perturber(agents) do
    if :rand.uniform() <= 0.2 do
      [Perturber | agents]
    else
      agents
    end
  end
end
