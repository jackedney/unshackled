defmodule Unshackled.Evolution.ClaimChangeDetector do
  @moduledoc """
  Module for detecting meaningful claim changes between cycles.

  This module compares consecutive trajectory point claims using semantic
  similarity to identify when claims meaningfully change, records transitions,
  and classifies the type of change.
  """

  alias Unshackled.Agents.AgentContribution
  alias Unshackled.Embedding.Similarity
  alias Unshackled.Embedding.TrajectoryPoint
  alias Unshackled.Evolution.ClaimDiff
  alias Unshackled.Evolution.ClaimTransition
  alias Unshackled.Evolution.Config
  alias Unshackled.LLM.Client
  alias Unshackled.Repo

  import Ecto.Query

  @type transition_map :: %{
          blackboard_id: pos_integer(),
          from_cycle: non_neg_integer(),
          to_cycle: pos_integer(),
          previous_claim: String.t(),
          new_claim: String.t(),
          trigger_agent: String.t(),
          trigger_contribution_id: pos_integer() | nil,
          change_type: String.t(),
          diff_additions: map(),
          diff_removals: map()
        }

  @doc """
  Detects and returns all claim transitions for a blackboard.

  Compares consecutive TrajectoryPoint.claim_text values using semantic
  similarity. Transitions are created when similarity < configured threshold.

  ## Parameters

  - blackboard_id: The blackboard ID to analyze

  ## Returns

  - {:ok, transitions} on success, where transitions is a list of ClaimTransition structs
  - {:error, reason} on failure

  ## Examples

      iex> {:ok, transitions} = ClaimChangeDetector.detect_changes(blackboard_id)
      iex> length(transitions) > 0
      true

  """
  @spec detect_changes(pos_integer()) :: {:ok, [ClaimTransition.t()]} | {:error, term()}
  def detect_changes(blackboard_id) when is_integer(blackboard_id) and blackboard_id > 0 do
    with {:ok, trajectory} <- fetch_trajectory(blackboard_id) do
      detect_transitions(trajectory)
    end
  end

  def detect_changes(_), do: {:error, :invalid_blackboard_id}

  @doc """
  Returns the most recent claim transition for a blackboard.

  ## Parameters

  - blackboard_id: The blackboard ID to query

  ## Returns

  - {:ok, %ClaimTransition{}} if a transition exists
  - {:ok, nil} if no transitions exist

  ## Examples

      iex> {:ok, transition} = ClaimChangeDetector.latest_change(blackboard_id)
      iex> transition.change_type
      "refinement"

  """
  @spec latest_change(pos_integer()) :: {:ok, ClaimTransition.t() | nil}
  def latest_change(blackboard_id) when is_integer(blackboard_id) and blackboard_id > 0 do
    query =
      from(ct in ClaimTransition,
        where: ct.blackboard_id == ^blackboard_id,
        order_by: [desc: ct.to_cycle],
        limit: 1
      )

    {:ok, Repo.one(query)}
  end

  def latest_change(_), do: {:error, :invalid_blackboard_id}

  @doc """
  Checks if a claim changed between two cycles.

  ## Parameters

  - blackboard_id: The blackboard ID to query
  - from_cycle: The starting cycle number
  - to_cycle: The ending cycle number

  ## Returns

  - true if a meaningful change occurred between the cycles
  - false otherwise

  ## Examples

      iex> ClaimChangeDetector.has_changed?(blackboard_id, 1, 3)
      true

      iex> ClaimChangeDetector.has_changed?(blackboard_id, 5, 6)
      false

  """
  @spec has_changed?(pos_integer(), non_neg_integer(), pos_integer()) :: boolean()
  def has_changed?(blackboard_id, from_cycle, to_cycle)
      when is_integer(blackboard_id) and blackboard_id > 0 and
             is_integer(from_cycle) and from_cycle >= 0 and
             is_integer(to_cycle) and to_cycle > from_cycle do
    query =
      from(ct in ClaimTransition,
        where:
          ct.blackboard_id == ^blackboard_id and ct.from_cycle >= ^from_cycle and
            ct.to_cycle <= ^to_cycle
      )

    Repo.exists?(query)
  end

  def has_changed?(_, _, _), do: false

  @spec fetch_trajectory(pos_integer()) :: {:ok, [TrajectoryPoint.t()]} | {:error, term()}
  defp fetch_trajectory(blackboard_id) do
    query =
      from(tp in TrajectoryPoint,
        where: tp.blackboard_id == ^blackboard_id,
        order_by: [asc: tp.cycle_number]
      )

    trajectory = Repo.all(query)

    if Enum.empty?(trajectory) do
      {:error, :no_trajectory_points}
    else
      {:ok, trajectory}
    end
  end

  @spec detect_transitions([TrajectoryPoint.t()]) ::
          {:ok, [ClaimTransition.t()]} | {:error, term()}
  defp detect_transitions(trajectory) when length(trajectory) < 2 do
    {:ok, []}
  end

  defp detect_transitions(trajectory) do
    blackboard_id = get_blackboard_id(trajectory)

    transitions =
      trajectory
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce([], fn [prev, curr], acc ->
        case detect_single_transition(blackboard_id, prev, curr) do
          {:ok, :no_change} -> acc
          {:ok, transition} -> [transition | acc]
          {:error, _} -> acc
        end
      end)
      |> Enum.reverse()

    {:ok, transitions}
  end

  @spec detect_single_transition(pos_integer(), TrajectoryPoint.t(), TrajectoryPoint.t()) ::
          {:ok, ClaimTransition.t()} | {:ok, :no_change} | {:error, term()}
  defp detect_single_transition(blackboard_id, prev, curr) do
    case fetch_existing_transition(blackboard_id, prev.cycle_number, curr.cycle_number) do
      {:ok, transition} ->
        {:ok, transition}

      :not_found ->
        with {:ok, similarity} <- compute_similarity(prev, curr),
             true <- similarity < Config.similarity_threshold() do
          build_and_store_transition(blackboard_id, prev, curr)
        else
          {:error, reason} -> {:error, reason}
          false -> {:ok, :no_change}
        end
    end
  end

  @spec fetch_existing_transition(pos_integer(), non_neg_integer(), pos_integer()) ::
          {:ok, ClaimTransition.t()} | :not_found
  defp fetch_existing_transition(blackboard_id, from_cycle, to_cycle) do
    query =
      from(ct in ClaimTransition,
        where:
          ct.blackboard_id == ^blackboard_id and ct.from_cycle == ^from_cycle and
            ct.to_cycle == ^to_cycle
      )

    case Repo.one(query) do
      nil -> :not_found
      transition -> {:ok, transition}
    end
  end

  @spec compute_similarity(TrajectoryPoint.t(), TrajectoryPoint.t()) ::
          {:ok, float()} | {:error, term()}
  defp compute_similarity(prev, curr) do
    with {:ok, prev_embedding} <- decode_embedding(prev),
         {:ok, curr_embedding} <- decode_embedding(curr) do
      Similarity.cosine_similarity(prev_embedding, curr_embedding)
    end
  end

  @spec build_and_store_transition(pos_integer(), TrajectoryPoint.t(), TrajectoryPoint.t()) ::
          {:ok, ClaimTransition.t()} | {:error, term()}
  defp build_and_store_transition(blackboard_id, prev, curr) do
    with {:ok, change_type} <- classify_change_type(prev.claim_text, curr.claim_text),
         {:ok, diff_data} <- ClaimDiff.generate_diff(prev.claim_text, curr.claim_text),
         {:ok, trigger_info} <- find_trigger_agent(blackboard_id, curr.cycle_number) do
      transition_attrs = %{
        blackboard_id: blackboard_id,
        from_cycle: prev.cycle_number,
        to_cycle: curr.cycle_number,
        previous_claim: prev.claim_text,
        new_claim: curr.claim_text,
        trigger_agent: trigger_info.agent_role,
        trigger_contribution_id: trigger_info.contribution_id,
        change_type: change_type,
        diff_additions: wrap_diff_list(diff_data.additions),
        diff_removals: wrap_diff_list(diff_data.removals)
      }

      store_transition(transition_attrs)
    end
  end

  @spec classify_change_type(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defp classify_change_type(previous_claim, new_claim) do
    model = Config.summarizer_model()

    messages = [
      %{
        role: "system",
        content:
          "You are a semantic change classifier. Analyze how a claim changed from one version to another."
      },
      %{
        role: "user",
        content: """
        Classify the change type between these two claims:

        Previous claim: #{previous_claim}

        New claim: #{new_claim}

        Your task:
        1. Determine the type of semantic change that occurred
        2. Return ONLY the change type as a plain string

        Valid change types:
        - refinement: The claim was clarified, made more specific, or polished without fundamentally changing meaning
        - pivot: The claim fundamentally changed direction, taking a different perspective or stance
        - expansion: The claim broadened in scope, adding new concepts or dimensions while keeping the original core
        - contraction: The claim narrowed in scope, becoming more focused by removing concepts or dimensions

        Rules:
        - Focus on the semantic meaning change, not word count
        - If the claim became more precise but same core meaning, classify as "refinement"
        - If the claim took a different stance or perspective, classify as "pivot"
        - If the claim added new concepts or dimensions, classify as "expansion"
        - If the claim removed concepts or became more focused, classify as "contraction"

        Examples:
        "AI will transform business" -> "Companies not adopting AI will lose competitive advantage"
        Change type: refinement (same core, more specific)

        "AI is beneficial" -> "AI poses significant risks to humanity"
        Change type: pivot (different stance)

        "AI helps businesses" -> "AI helps businesses with customer service, marketing, and operations"
        Change type: expansion (new dimensions added)

        "AI helps with customer service, marketing, and operations" -> "AI helps with customer service"
        Change type: contraction (narrowed scope)
        """
      }
    ]

    case Client.chat(model, messages) do
      {:ok, response_struct} ->
        change_type =
          response_struct.content
          |> String.trim()
          |> String.downcase()

        if Enum.member?(~w[refinement pivot expansion contraction], change_type) do
          {:ok, change_type}
        else
          {:ok, "refinement"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec find_trigger_agent(pos_integer(), pos_integer()) ::
          {:ok, %{agent_role: String.t(), contribution_id: pos_integer() | nil}}
  defp find_trigger_agent(blackboard_id, cycle_number) do
    query =
      from(ac in AgentContribution,
        where:
          ac.blackboard_id == ^blackboard_id and ac.cycle_number == ^cycle_number and
            ac.accepted == true,
        order_by: [desc: ac.support_delta],
        limit: 1
      )

    case Repo.one(query) do
      nil ->
        query =
          from(ac in AgentContribution,
            where:
              ac.blackboard_id == ^blackboard_id and ac.cycle_number == ^cycle_number and
                ac.accepted == true,
            limit: 1
          )

        case Repo.one(query) do
          nil ->
            {:ok, %{agent_role: "unknown", contribution_id: nil}}

          contribution ->
            {:ok, %{agent_role: contribution.agent_role, contribution_id: contribution.id}}
        end

      contribution ->
        {:ok, %{agent_role: contribution.agent_role, contribution_id: contribution.id}}
    end
  end

  @spec decode_embedding(TrajectoryPoint.t()) :: {:ok, Nx.Tensor.t()} | {:error, String.t()}
  defp decode_embedding(%TrajectoryPoint{embedding_vector: embedding})
       when is_binary(embedding) do
    {:ok, :erlang.binary_to_term(embedding)}
  rescue
    _ -> {:error, "Failed to decode embedding"}
  end

  defp decode_embedding(%TrajectoryPoint{embedding_vector: %Nx.Tensor{} = embedding}) do
    {:ok, embedding}
  end

  defp decode_embedding(_), do: {:error, "Invalid embedding format"}

  @spec store_transition(map()) :: {:ok, ClaimTransition.t()} | {:error, Ecto.Changeset.t()}
  defp store_transition(attrs) do
    changeset = ClaimTransition.changeset(%ClaimTransition{}, attrs)

    case Repo.insert(changeset, on_conflict: :nothing) do
      {:ok, transition} -> {:ok, transition}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec wrap_diff_list(list() | map()) :: map()
  defp wrap_diff_list(items) when is_list(items), do: %{"items" => items}
  defp wrap_diff_list(items) when is_map(items), do: items
  defp wrap_diff_list(_), do: %{}

  @spec get_blackboard_id([TrajectoryPoint.t()]) :: pos_integer()
  defp get_blackboard_id(trajectory) do
    case trajectory do
      [%TrajectoryPoint{blackboard_id: id} | _] -> id
      _ -> raise "Invalid trajectory"
    end
  end
end
