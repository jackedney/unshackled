defmodule Unshackled.Agents.Cartographer do
  @moduledoc """
  Cartographer agent that navigates the embedding space.

  The Cartographer agent has SPECIAL ACCESS to trajectory visualization data
  from TrajectoryPoint records. It detects when the swarm is stuck in a
  local basin (stagnation) and suggests pivots toward underexplored regions
  of the embedding space.
  """

  @behaviour Unshackled.Agents.Agent

  alias Unshackled.Agents.Agent
  alias Unshackled.Agents.PromptBuilder
  alias Unshackled.Agents.Responses.CartographerSchema
  alias Unshackled.Blackboard.Server
  alias Unshackled.Embedding.TrajectoryPoint
  alias Unshackled.Repo
  import Ecto.Changeset

  import Ecto.Query

  @doc """
  Returns the agent's role.
  """
  @impl true
  @spec role() :: :cartographer
  def role, do: :cartographer

  @doc """
  Builds a prompt from the current blackboard state and trajectory data.

  The agent activates only when stagnation is detected (low trajectory movement
  for 5+ cycles). The prompt includes the current position, trajectory history,
  and identification of underexplored regions in the embedding space.

  Stagnation is calculated as:
  - Average movement between consecutive trajectory points over last 5+ cycles
  - Movement threshold: < 0.1 (normalized distance between embeddings)
  """
  @impl true
  @spec build_prompt(Server.t()) :: String.t()
  def build_prompt(%Server{
        blackboard_id: blackboard_id,
        cycle_count: current_cycle,
        current_claim: claim
      })
      when is_integer(blackboard_id) and is_integer(current_cycle) and current_cycle >= 5 do
    trajectory_data = fetch_trajectory_data(blackboard_id, current_cycle)

    case detect_stagnation(trajectory_data) do
      {false, _} ->
        build_error_prompt(
          claim,
          current_cycle,
          "No stagnation detected - trajectory movement is adequate"
        )

      {true, stagnation_metrics} ->
        build_guidance_prompt(claim, current_cycle, trajectory_data, stagnation_metrics)
    end
  end

  def build_prompt(%Server{
        blackboard_id: blackboard_id,
        cycle_count: current_cycle,
        current_claim: claim
      })
      when is_integer(blackboard_id) and is_integer(current_cycle) do
    build_error_prompt(
      claim,
      current_cycle,
      "Insufficient trajectory data (need at least 5 cycles) - cannot detect stagnation"
    )
  end

  def build_prompt(%Server{current_claim: claim, cycle_count: current_cycle}) do
    build_error_prompt(
      claim,
      current_cycle,
      "No blackboard_id available - cannot access trajectory data"
    )
  end

  @spec build_guidance_prompt(String.t(), integer(), list(), map()) :: String.t()
  defp build_guidance_prompt(claim, current_cycle, trajectory_data, stagnation_metrics) do
    trajectory_history_text = format_trajectory_history(trajectory_data)
    current_position_text = format_current_position(List.last(trajectory_data))
    underexplored_regions_text = identify_underexplored_regions(trajectory_data)

    average_movement = Map.get(stagnation_metrics, :average_movement, 0.0)

    """
    You are analyzing trajectory stagnation in the embedding space and suggesting navigation guidance.

    Current claim (Cycle #{current_cycle}):
    "#{claim}"

    Current position in embedding space:
    #{current_position_text}

    Trajectory history (last 5+ cycles):
    #{trajectory_history_text}

    STAGNATION DETECTED:
    - Average trajectory movement: #{:erlang.float_to_binary(average_movement, decimals: 4)}
    - Movement below stagnation threshold (0.1) for 5+ consecutive cycles
    - Swarm appears stuck in a local basin of the embedding space

    Underexplored regions in embedding space:
    #{underexplored_regions_text}

    Your task:
    1. Suggest a new direction to move the swarm out of the current basin.
    2. Identify a target region in the embedding space that is underexplored.
    3. Provide a clear rationale for why this direction would be productive.

    CRITICAL: You have SPECIAL ACCESS to trajectory visualization data showing:
    - The exact path taken through embedding space over recent cycles
    - Regions that have been heavily explored (dense clusters of trajectory points)
    - Regions that remain underexplored (sparse or unvisited areas)

    Use this spatial understanding to guide the swarm toward novel, unexplored territory.

    #{PromptBuilder.json_instructions(%{suggested_direction: "vector or description of direction in embedding space", target_region: "description of underexplored region to explore", exploration_rationale: "why this direction is productive, what new territory it opens"})}

    Example (stuck in local basin):
    If trajectory shows repeated visits to same cluster around "local thermodynamics"
    And underexplored region is "quantum information theory interpretations"
    Valid response:
    {
      "suggested_direction": "Pivot from thermodynamics toward information-theoretic interpretations of entropy",
      "target_region": "Quantum information theory space - entropy as information loss in decoherence processes",
      "exploration_rationale": "Current trajectory shows swarm oscillating in classical thermodynamics basin. Quantum information theory offers fundamentally different framing (entropy as information) that connects to unexplored semantic space and may reveal novel inferences about locality constraints."
    }

    Example (stuck in narrow precision debates):
    If trajectory shows cycling through numerical threshold refinements
    And underexplored region is "causal mechanism exploration"
    Valid response:
    {
      "suggested_direction": "Shift focus from quantitative thresholds to underlying causal mechanisms",
      "target_region": "Causal reasoning space - why entropy increases locally, not just where boundaries are",
      "exploration_rationale": "Swarm is trapped in precision refinement loop. Exploring causal mechanisms (information flow, energy transfer pathways, decoherence origins) would move to new semantic territory and reveal fundamentally different explanatory dimensions."
    }

    Respond with valid JSON only.
    """
  end

  @spec build_error_prompt(String.t(), integer(), String.t()) :: String.t()
  defp build_error_prompt(claim, current_cycle, error_reason) do
    """
    ERROR: Cartographer should not be activated when stagnation is not detected.

    Current claim (Cycle #{current_cycle}):
    "#{claim}"

    Reason for error:
    #{error_reason}

    The Cartographer only activates when stagnation is detected (low trajectory movement for 5+ cycles).
    This is an error in agent scheduling.

    #{PromptBuilder.json_instructions(%{suggested_direction: "", target_region: "", exploration_rationale: "Error: #{error_reason}"})}

    Respond with valid JSON only.
    """
  end

  @doc """
  Parses the LLM response and validates it against the Cartographer schema.

  Returns {:ok, %CartographerSchema{}} on valid response.
  Returns {:error, changeset} on invalid response.
  """
  @impl true
  @spec parse_response(String.t()) :: {:ok, CartographerSchema.t()} | {:error, Ecto.Changeset.t()}
  def parse_response(response) do
    case Agent.decode_json_response(response) do
      {:ok, data} ->
        attrs = %{
          suggested_direction: Map.get(data, "suggested_direction"),
          target_region: Map.get(data, "target_region"),
          exploration_rationale: Map.get(data, "exploration_rationale")
        }

        schema = %CartographerSchema{}
        changeset = CartographerSchema.changeset(schema, attrs)

        if changeset.valid? do
          schema_with_data = apply_changes(changeset)
          {:ok, schema_with_data}
        else
          {:error, changeset}
        end

      {:error, _reason} ->
        schema = %CartographerSchema{}
        changeset = CartographerSchema.changeset(schema, %{})
        {:error, add_error(changeset, :json, "Invalid JSON format")}
    end
  end

  @doc """
  Returns the confidence delta for the Cartographer agent.

  The Cartographer is advisory only and returns 0 confidence delta.
  It provides navigation guidance but does not directly impact confidence.
  """
  @impl true
  @spec confidence_delta({:ok, CartographerSchema.t()} | {:error, Ecto.Changeset.t()}) :: float()
  def confidence_delta({:ok, _schema}), do: 0.0

  def confidence_delta({:error, _changeset}), do: 0.0

  @spec fetch_trajectory_data(pos_integer(), integer()) :: list(map())
  defp fetch_trajectory_data(blackboard_id, current_cycle) do
    from_cycle = max(0, current_cycle - 5)

    query =
      from(
        t in TrajectoryPoint,
        where: t.blackboard_id == ^blackboard_id,
        where: t.cycle_number >= ^from_cycle and t.cycle_number <= ^current_cycle,
        order_by: [asc: t.cycle_number]
      )

    Enum.map(Repo.all(query), &trajectory_point_to_map/1)
  end

  @spec trajectory_point_to_map(TrajectoryPoint.t()) :: map()
  defp trajectory_point_to_map(point) do
    %{
      cycle_number: point.cycle_number,
      claim_text: point.claim_text,
      support_strength: point.support_strength,
      embedding_vector: point.embedding_vector
    }
  end

  @spec detect_stagnation(list(map())) :: {boolean(), map()}
  defp detect_stagnation(trajectory_points) when length(trajectory_points) < 2 do
    {false, %{reason: "Insufficient trajectory points"}}
  end

  defp detect_stagnation(trajectory_points) do
    movements = calculate_movements(trajectory_points)

    if length(movements) < 5 do
      {false, %{reason: "Need at least 5 movement measurements"}}
    else
      average_movement = Enum.sum(movements) / length(movements)
      is_stagnant = average_movement < 0.1

      metrics = %{
        average_movement: average_movement,
        movement_count: length(movements),
        min_movement: Enum.min(movements),
        max_movement: Enum.max(movements)
      }

      {is_stagnant, metrics}
    end
  end

  @spec calculate_movements(list(map())) :: list(float())
  defp calculate_movements([]), do: []

  defp calculate_movements([_]), do: []

  defp calculate_movements(trajectory_points) do
    trajectory_points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [p1, p2] ->
      calculate_embedding_distance(p1.embedding_vector, p2.embedding_vector)
    end)
  end

  @spec calculate_embedding_distance(binary(), binary()) :: float()
  defp calculate_embedding_distance(embedding1, embedding2)
       when is_binary(embedding1) and is_binary(embedding2) do
    vec1 = embedding_vector_to_list(embedding1)
    vec2 = embedding_vector_to_list(embedding2)

    euclidean_distance(vec1, vec2)
  rescue
    _ -> 0.0
  end

  defp calculate_embedding_distance(_, _), do: 0.0

  @spec embedding_vector_to_list(binary()) :: list(float())
  defp embedding_vector_to_list(embedding_binary) do
    embedding_binary
    |> :erlang.binary_to_term()
    |> Tuple.to_list()
  end

  @spec euclidean_distance(list(float()), list(float())) :: float()
  defp euclidean_distance(vec1, vec2) when length(vec1) == length(vec2) do
    vec1
    |> Enum.zip(vec2)
    |> Enum.map(fn {a, b} -> :math.pow(a - b, 2) end)
    |> Enum.sum()
    |> :math.sqrt()
  end

  defp euclidean_distance(_, _), do: 0.0

  @spec format_trajectory_history(list(map())) :: String.t()
  defp format_trajectory_history([]), do: "No trajectory data available."

  defp format_trajectory_history(trajectory_points) do
    formatted_points =
      Enum.map(
        trajectory_points,
        fn point ->
          movement_info = calculate_movement_info(point, trajectory_points)

          "  Cycle #{point.cycle_number}: \"#{point.claim_text}\" (support: #{point.support_strength})#{movement_info}"
        end
      )

    Enum.join(formatted_points, "\n")
  end

  @spec calculate_movement_info(map(), list(map())) :: String.t()
  defp calculate_movement_info(point, trajectory_points) do
    if point.cycle_number > 0 do
      previous_point =
        Enum.find(trajectory_points, fn p -> p.cycle_number == point.cycle_number - 1 end)

      if previous_point do
        distance =
          calculate_embedding_distance(
            previous_point.embedding_vector,
            point.embedding_vector
          )

        " (movement: #{:erlang.float_to_binary(distance, decimals: 4)})"
      else
        ""
      end
    else
      ""
    end
  end

  @spec format_current_position(map() | nil) :: String.t()
  defp format_current_position(nil), do: "No current position data available."

  defp format_current_position(point) do
    """
    - Claim: "#{point.claim_text}"
    - Support strength: #{point.support_strength}
    - Cycle: #{point.cycle_number}
    """
  end

  @spec identify_underexplored_regions(list(map())) :: String.t()
  defp identify_underexplored_regions([]), do: "No trajectory data to analyze regions."

  defp identify_underexplored_regions(trajectory_points) do
    claim_texts = Enum.map(trajectory_points, & &1.claim_text)

    explored_themes =
      claim_texts
      |> Enum.flat_map(&extract_themes/1)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_theme, count} -> count end, :desc)

    frequent_themes =
      explored_themes
      |> Enum.take(5)
      |> Enum.map_join("\n", fn {theme, _count} -> "- #{theme}" end)

    if String.length(frequent_themes) > 0 do
      """
      Heavily explored themes (avoid):
      #{frequent_themes}

      Underexplored themes to explore:
      - Alternative domain translations (e.g., biology, economics interpretations of current physics concept)
      - Causal mechanisms rather than quantitative descriptions
      - Foundational assumptions questioning (e.g., "What if entropy is emergent rather than fundamental?")
      - Cross-analogy mappings to distant domains
      - Boundary condition exploration at extreme scales
      """
    else
      """
      - Alternative domains beyond current conceptual framework
      - Foundational assumptions and first principles
      - Causal mechanisms and underlying processes
      - Boundary conditions and edge cases
      """
    end
  end

  @spec extract_themes(String.t()) :: list(String.t())
  defp extract_themes(claim_text) do
    keywords = [
      "entropy",
      "thermodynamics",
      "local",
      "quantum",
      "decoherence",
      "isolation",
      "system",
      "scale",
      "information",
      "causal",
      "mechanism",
      "boundary",
      "energy",
      "heat",
      "temperature",
      "physics",
      "mathematics",
      "economics",
      "biology",
      "philosophy"
    ]

    lower_text = String.downcase(claim_text)

    Enum.filter(keywords, &String.contains?(lower_text, &1))
  end
end
