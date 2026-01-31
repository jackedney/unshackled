defmodule Unshackled.Cycle.Arbiter do
  @moduledoc """
  Arbiter applies rule-based selection of which agent outputs to accept.

  The Arbiter evaluates agent results from each cycle and applies
  confidence dynamics rules to determine which contributions should be accepted
  and their associated confidence deltas.

  ## Acceptance Rules

  - Explorer extension: Accept if no Critic objection targets it
  - Critic objection: Accept if logically valid (targets premise not conclusion)
  - Connector analogy: Accept if specific enough (has testable mapping)
  - Other agents: Accept if output is valid (properly formatted)
  """

  alias Unshackled.Blackboard.Server

  @type agent_result :: {:ok, atom(), String.t(), map(), float()} | {:error, term()}
  @type accepted_contribution :: %{
          role: atom(),
          model_used: String.t(),
          output: map(),
          confidence_delta: float()
        }

  @doc """
  Evaluates agent results and returns accepted contributions with confidence deltas.

  ## Parameters

  - agent_results: List of agent results from the cycle
  - blackboard_state: Current blackboard state

  ## Returns

  {:ok, accepted_contributions} where accepted_contributions is a list of maps:
  - role: Agent role (:explorer, :critic, :connector, etc.)
  - model_used: LLM model that generated the output
  - output: The parsed agent output
  - confidence_delta: The confidence delta to apply

  {:error, reason} if evaluation fails

  ## Examples

      iex> results = [{:ok, :explorer, "gpt-4", %{valid: true, new_claim: "X"}, 0.10},
      ...>            {:ok, :critic, "claude-3", %{valid: true, objection: "Y", target_premise: "Z"}, -0.15}]
      iex> {:ok, accepted} = Arbiter.evaluate(results, state)
      iex> length(accepted)
      2

      # Example: Critic objection targets conclusion, rejected
      iex> results = [{:ok, :critic, "claude-3",
      ...>            %{valid: false, error: "Objection targets conclusion rather than premise"}, 0.0}]
      iex> {:ok, accepted} = Arbiter.evaluate(results, state)
      iex> length(accepted)
      0

      # Example: Invalid agent output format
      iex> results = [{:error, {:timeout, 60000}}]
      iex> {:ok, accepted} = Arbiter.evaluate(results, state)
      iex> length(accepted)
      0
  """
  @spec evaluate([agent_result()], Server.t()) ::
          {:ok, [map()]} | {:error, String.t()}
  def evaluate(agent_results, _blackboard_state) do
    valid_results = filter_valid_results(agent_results)

    explorer_outputs = collect_outputs_by_role(valid_results, :explorer)
    critic_outputs = collect_outputs_by_role(valid_results, :critic)
    connector_outputs = collect_outputs_by_role(valid_results, :connector)
    other_outputs = collect_other_outputs(valid_results, [:explorer, :critic, :connector])

    accepted_explorers = evaluate_explorers(explorer_outputs, critic_outputs)
    accepted_critics = evaluate_critics(critic_outputs)
    accepted_connectors = evaluate_connectors(connector_outputs)
    accepted_others = evaluate_others(other_outputs)

    all_accepted =
      Enum.concat([
        accepted_explorers,
        accepted_critics,
        accepted_connectors,
        accepted_others
      ])

    {:ok, all_accepted}
  end

  @spec filter_valid_results([agent_result()]) :: [agent_result()]
  defp filter_valid_results(agent_results) when is_list(agent_results) do
    Enum.filter(agent_results, fn
      {:ok, _role, _model, output, _delta} when is_map(output) ->
        Map.get(output, :valid, false)

      _ ->
        false
    end)
  end

  @spec collect_outputs_by_role([agent_result()], atom()) :: [map()]
  defp collect_outputs_by_role(agent_results, role) when is_list(agent_results) do
    Enum.reduce(agent_results, [], fn
      {:ok, ^role, model, output, delta}, acc ->
        [%{role: role, model_used: model, output: output, confidence_delta: delta} | acc]

      _, acc ->
        acc
    end)
  end

  @spec collect_other_outputs([agent_result()], [atom()]) :: [map()]
  defp collect_other_outputs(agent_results, exclude_roles) when is_list(agent_results) do
    exclude_roles_set = MapSet.new(exclude_roles)

    Enum.reduce(agent_results, [], fn
      {:ok, role, model, output, delta}, acc ->
        if MapSet.member?(exclude_roles_set, role) do
          acc
        else
          [%{role: role, model_used: model, output: output, confidence_delta: delta} | acc]
        end

      _, acc ->
        acc
    end)
  end

  @spec evaluate_explorers([map()], [map()]) :: [map()]
  defp evaluate_explorers(explorer_outputs, critic_outputs) do
    Enum.filter(explorer_outputs, fn explorer ->
      not critic_targets_explorer?(explorer, critic_outputs)
    end)
  end

  @spec critic_targets_explorer?(map(), [map()]) :: boolean()
  defp critic_targets_explorer?(explorer, critic_outputs) do
    explorer_claim = Map.get(explorer.output, :new_claim, "")

    valid_critics =
      Enum.filter(critic_outputs, fn critic ->
        Map.get(critic.output, :valid, false)
      end)

    Enum.any?(valid_critics, fn critic ->
      target_premise = Map.get(critic.output, :target_premise, "")
      premises_similar?(target_premise, explorer_claim)
    end)
  end

  @spec premises_similar?(String.t() | nil, String.t() | nil) :: boolean()
  defp premises_similar?(premise, claim) do
    lower_premise = String.downcase(String.trim(premise || ""))
    lower_claim = String.downcase(String.trim(claim || ""))

    cond do
      String.length(lower_premise) < 5 or String.length(lower_claim) < 5 ->
        false

      lower_claim == lower_premise ->
        true

      true ->
        false
    end
  end

  @spec evaluate_critics([map()]) :: [map()]
  defp evaluate_critics(critic_outputs) do
    Enum.filter(critic_outputs, fn critic ->
      Map.get(critic.output, :valid, false)
    end)
  end

  @spec evaluate_connectors([map()]) :: [map()]
  defp evaluate_connectors(connector_outputs) do
    Enum.filter(connector_outputs, fn connector ->
      Map.get(connector.output, :valid, false)
    end)
  end

  @spec evaluate_others([map()]) :: [map()]
  defp evaluate_others(other_outputs) do
    Enum.filter(other_outputs, fn agent ->
      Map.get(agent.output, :valid, false)
    end)
  end
end
