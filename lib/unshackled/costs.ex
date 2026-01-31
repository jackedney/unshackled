defmodule Unshackled.Costs do
  @moduledoc """
  Context module for querying LLM cost data.

  This module provides functions for aggregating and querying cost data
  stored in the llm_costs table. All queries use indexed lookups for
  efficient performance.

  ## Functions

  * `get_session_total_cost/1` - Get total cost for a session
  * `get_cost_by_cycle/1` - Get cost breakdown by cycle number
  * `get_cost_by_agent/1` - Get cost breakdown by agent role

  """

  import Ecto.Query

  alias Unshackled.Costs.LLMCost
  alias Unshackled.Repo

  @doc """
  Returns the total cost in USD for a given session.

  Returns 0.0 if the session has no cost records or doesn't exist.

  ## Examples

      iex> Unshackled.Costs.get_session_total_cost(1)
      0.0234

      iex> Unshackled.Costs.get_session_total_cost(999)
      0.0

  """
  @spec get_session_total_cost(integer()) :: float()
  def get_session_total_cost(blackboard_id) when is_integer(blackboard_id) do
    query =
      from c in LLMCost,
        where: c.blackboard_id == ^blackboard_id,
        select: sum(c.cost_usd)

    case Repo.one(query) do
      nil -> 0.0
      total when is_number(total) -> total / 1
    end
  end

  @doc """
  Returns cost breakdown by cycle for a given session.

  Returns a list of maps with keys :cycle_number, :total_cost, and :total_tokens.
  Sorted by cycle_number descending (most recent first).

  Returns empty list if the session has no cost records or doesn't exist.

  ## Examples

      iex> Unshackled.Costs.get_cost_by_cycle(1)
      [
        %{cycle_number: 5, total_cost: 0.0012, total_tokens: 200},
        %{cycle_number: 4, total_cost: 0.0015, total_tokens: 250}
      ]

      iex> Unshackled.Costs.get_cost_by_cycle(999)
      []

  """
  @spec get_cost_by_cycle(integer()) :: [
          %{cycle_number: integer(), total_cost: float(), total_tokens: integer()}
        ]
  def get_cost_by_cycle(blackboard_id) when is_integer(blackboard_id) do
    query =
      from c in LLMCost,
        where: c.blackboard_id == ^blackboard_id,
        group_by: c.cycle_number,
        select: %{
          cycle_number: c.cycle_number,
          total_cost: sum(c.cost_usd),
          total_tokens: sum(c.input_tokens + c.output_tokens)
        },
        order_by: [desc: c.cycle_number]

    Repo.all(query)
  end

  @doc """
  Returns cost breakdown by agent for a given session.

  Returns a list of maps with keys :agent_role, :total_cost, and :call_count.
  Sorted by total_cost descending.

  Returns empty list if the session has no cost records or doesn't exist.

  ## Examples

      iex> Unshackled.Costs.get_cost_by_agent(1)
      [
        %{agent_role: "explorer", total_cost: 0.012, call_count: 10},
        %{agent_role: "critic", total_cost: 0.008, call_count: 10}
      ]

      iex> Unshackled.Costs.get_cost_by_agent(999)
      []

  """
  @spec get_cost_by_agent(integer()) :: [
          %{agent_role: String.t(), total_cost: float(), call_count: integer()}
        ]
  def get_cost_by_agent(blackboard_id) when is_integer(blackboard_id) do
    query =
      from c in LLMCost,
        where: c.blackboard_id == ^blackboard_id,
        group_by: c.agent_role,
        select: %{
          agent_role: c.agent_role,
          total_cost: sum(c.cost_usd),
          call_count: count(c.id)
        },
        order_by: [desc: sum(c.cost_usd)]

    Repo.all(query)
  end
end
