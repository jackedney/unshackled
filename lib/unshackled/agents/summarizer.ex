defmodule Unshackled.Agents.Summarizer do
  @moduledoc """
  Agent for generating context summaries that resolve implicit references in claims.

  The Summarizer uses a sliding context window approach:
  - Receives the last 5 cycles of claim history and agent contributions
  - Uses the summary from 5 cycles ago as foundational context
  - Generates summaries that make implicit references explicit

  This bounded context approach keeps token usage manageable while preserving
  continuity through chained summaries.
  """

  alias Unshackled.Agents.Agent
  alias Unshackled.Repo
  alias Unshackled.Evolution.ClaimSummary
  alias Unshackled.Evolution.Config
  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Blackboard.BlackboardSnapshot
  alias Unshackled.Agents.AgentContribution
  alias Unshackled.LLM.Client
  alias UnshackledWeb.PubSub, as: WebPubSub

  import Ecto.Query

  @doc """
  Generates a ClaimSummary for the given blackboard_id.

  Receives:
  - Current claim
  - Last 5 cycles of claim history (snapshots)
  - Last 5 cycles of agent contributions (accepted and rejected)
  - Summary from 5 cycles ago (if available) as foundational context

  Outputs:
  - full_context_summary: Claim rewritten with implicit references explicit
  - evolution_narrative: 2-3 sentence summary of the claim's evolution
  - addressed_objections: List of objections that have been addressed
  - remaining_gaps: List of ambiguities that still exist

  Returns {:ok, %ClaimSummary{}} on success.
  Returns {:error, :no_claims} if no claim history exists.
  Returns {:error, reason} on other errors.

  ## Examples

      iex> {:ok, summary} = Summarizer.summarize(blackboard_id)
      iex> is_binary(summary.full_context_summary)
      true

      iex> Summarizer.summarize(blackboard_id_without_claims)
      {:error, :no_claims}
  """
  @context_window_cycles 5

  @spec summarize(pos_integer()) :: {:ok, ClaimSummary.t()} | {:error, term()}
  def summarize(blackboard_id) when is_integer(blackboard_id) do
    with {:ok, blackboard} <- fetch_blackboard(blackboard_id),
         {:ok, snapshots} <- fetch_recent_snapshots(blackboard_id, blackboard.cycle_count),
         {:ok, contributions} <- fetch_recent_contributions(blackboard_id, blackboard.cycle_count),
         previous_summary <- fetch_previous_summary(blackboard_id, blackboard.cycle_count),
         {:ok, summary_data} <-
           generate_summary(blackboard, snapshots, contributions, previous_summary),
         {:ok, claim_summary} <- store_summary(blackboard_id, summary_data) do
      broadcast_summary_updated(blackboard_id, claim_summary)
      {:ok, claim_summary}
    end
  end

  @doc """
  Retrieves the most recent summary for a blackboard.

  Returns {:ok, %ClaimSummary{}} if a summary exists.
  Returns {:error, :not_found} if no summary exists.
  """
  @spec get_latest_summary(pos_integer()) :: {:ok, ClaimSummary.t()} | {:error, :not_found}
  def get_latest_summary(blackboard_id) when is_integer(blackboard_id) do
    query =
      from(cs in ClaimSummary,
        where: cs.blackboard_id == ^blackboard_id,
        order_by: [desc: cs.cycle_number],
        limit: 1
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      summary -> {:ok, summary}
    end
  end

  defp fetch_blackboard(blackboard_id) do
    case Repo.get(BlackboardRecord, blackboard_id) do
      nil -> {:error, :blackboard_not_found}
      blackboard -> {:ok, blackboard}
    end
  end

  defp fetch_recent_snapshots(blackboard_id, current_cycle) do
    min_cycle = max(1, current_cycle - @context_window_cycles + 1)

    query =
      from(bs in BlackboardSnapshot,
        where: bs.blackboard_id == ^blackboard_id,
        where: bs.cycle_number >= ^min_cycle,
        order_by: [asc: bs.cycle_number]
      )

    snapshots = Repo.all(query)

    if Enum.empty?(snapshots) do
      {:error, :no_claims}
    else
      {:ok, snapshots}
    end
  end

  defp fetch_recent_contributions(blackboard_id, current_cycle) do
    min_cycle = max(1, current_cycle - @context_window_cycles + 1)

    query =
      from(ac in AgentContribution,
        where: ac.blackboard_id == ^blackboard_id,
        where: ac.cycle_number >= ^min_cycle,
        order_by: [asc: ac.cycle_number]
      )

    {:ok, Repo.all(query)}
  end

  defp fetch_previous_summary(blackboard_id, current_cycle) do
    # Get the summary from approximately 5 cycles ago
    target_cycle = current_cycle - @context_window_cycles

    if target_cycle < 1 do
      nil
    else
      query =
        from(cs in ClaimSummary,
          where: cs.blackboard_id == ^blackboard_id,
          where: cs.cycle_number <= ^target_cycle,
          order_by: [desc: cs.cycle_number],
          limit: 1
        )

      Repo.one(query)
    end
  end

  defp generate_summary(blackboard, snapshots, contributions, previous_summary) do
    current_claim = blackboard.current_claim
    claim_history = claim_history_from_snapshots(snapshots)
    critic_objections = extract_critic_objections(contributions)
    other_refinements = extract_refinements(contributions)
    cycle_number = blackboard.cycle_count

    prompt =
      build_summary_prompt(
        current_claim,
        claim_history,
        critic_objections,
        other_refinements,
        previous_summary
      )

    model = Config.summarizer_model()

    messages = [
      %{
        role: "system",
        content: """
        You are a context summarizer specialized in making implicit references explicit in evolving claims.
        Your goal is to help users understand claims without reviewing the full history.
        """
      },
      %{
        role: "user",
        content: prompt
      }
    ]

    case Client.chat(model, messages) do
      {:ok, response_struct} ->
        parse_summary_response(response_struct.content, cycle_number)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp claim_history_from_snapshots(snapshots) do
    Enum.map(snapshots, fn s ->
      %{
        cycle: s.cycle_number,
        claim: get_claim_from_snapshot(s)
      }
    end)
  end

  defp get_claim_from_snapshot(snapshot) do
    case snapshot.state_json do
      nil -> nil
      state when is_map(state) -> Map.get(state, "current_claim")
    end
  end

  defp extract_critic_objections(contributions) do
    contributions
    |> Enum.filter(fn ac -> ac.agent_role == "critic" end)
    |> Enum.map(fn ac ->
      %{
        cycle: ac.cycle_number,
        objection: extract_output_field(ac.output_text, "objection"),
        clarifying_question: extract_output_field(ac.output_text, "clarifying_question"),
        accepted: ac.accepted
      }
    end)
    |> Enum.filter(fn obj ->
      is_binary(obj.objection) and String.length(obj.objection) > 0
    end)
  end

  defp extract_refinements(contributions) do
    contributions
    |> Enum.filter(fn ac -> ac.agent_role != "critic" end)
    |> Enum.map(fn ac ->
      %{
        cycle: ac.cycle_number,
        agent: ac.agent_role,
        output: ac.output_text,
        accepted: ac.accepted
      }
    end)
  end

  defp extract_output_field(output_text, field_name) do
    case Jason.decode(output_text) do
      {:ok, decoded} when is_map(decoded) -> Map.get(decoded, field_name)
      _ -> nil
    end
  end

  defp build_summary_prompt(
         current_claim,
         claim_history,
         critic_objections,
         other_refinements,
         previous_summary
       ) do
    claim_history_text = claim_history_to_text(claim_history)
    objections_text = objections_to_text(critic_objections)
    refinements_text = refinements_to_text(other_refinements)
    previous_summary_text = previous_summary_to_text(previous_summary)

    """
    Analyze the claim evolution and generate a context summary.

    CURRENT CLAIM:
    #{current_claim}

    #{previous_summary_text}

    RECENT CLAIM HISTORY (last 5 cycles, chronological):
    #{claim_history_text}

    RECENT CRITIC OBJECTIONS (last 5 cycles):
    #{objections_text}

    RECENT REFINEMENTS FROM OTHER AGENTS (last 5 cycles):
    #{refinements_text}

    Your task:
    1. Identify all implicit references (pronouns, vague terms like "their", "it", "they", "the result", "the conclusion")
    2. Resolve each implicit reference by making it explicit based on the previous summary and recent history
    3. Generate a full_context_summary: rewrite the current claim with all implicit references made explicit
    4. Generate an evolution_narrative: 2-3 sentences explaining how the claim evolved (from the previous summary state if available, otherwise from the earliest claim in history)
    5. List addressed_objections: objections that have been addressed in the current claim
    6. List remaining_gaps: ambiguities or unresolved issues that still exist

    Return ONLY valid JSON in this format:
    {
      "full_context_summary": "The claim with all implicit references made explicit, complete and unambiguous",
      "evolution_narrative": "2-3 sentence narrative explaining the claim's evolution",
      "addressed_objections": ["objection 1", "objection 2"],
      "remaining_gaps": ["gap 1", "gap 2"]
    }

    Rules:
    - The full_context_summary must be a complete, standalone claim that needs no additional context
    - CRITICAL: The full_context_summary must start with the SUBJECT of the claim (a noun phrase), NOT a transitional word. NEVER begin with: "Therefore", "Consequently", "Thus", "Hence", "As a result", "Accordingly", "So", "In conclusion", "Ultimately", "Finally". These words are FORBIDDEN as opening words.
    - Replace ALL pronouns and vague references with their explicit referents
    - Use the previous summary as foundational context when resolving references from earlier cycles
    - If "their long-term competitive advantage erodes" becomes "Companies that choose not to invest in AI technologies will experience erosion of their long-term competitive advantage relative to competitors who invest aggressively in AI capabilities"
    - evolution_narrative should be concise (2-3 sentences maximum)
    - addressed_objections should list specific objections that were addressed
    - remaining_gaps should identify any remaining ambiguities or unresolved questions
    - Keep all lists concise (maximum 5 items each)
    - Be specific: use concrete terms, not vague generalizations

    Example:
    Current: "Consequently, their long-term competitive advantage erodes over time."
    Previous Summary: "Companies not investing in AI will face competitive disadvantage."
    History shows discussion of non-adoption consequences and competitive dynamics.

    Result:
    {
      "full_context_summary": "Companies that choose not to invest in AI technologies will experience erosion of their long-term competitive advantage relative to competitors who invest aggressively in AI capabilities.",
      "evolution_narrative": "The claim evolved from a general warning about non-adoption to a specific prediction about competitive advantage erosion. The focus shifted from falling behind to the mechanics of losing market position.",
      "addressed_objections": ["Whether competitive advantage loss is immediate or gradual", "What specific advantage is at risk"],
      "remaining_gaps": ["Timeframe for competitive advantage erosion", "Definition of 'aggressive' AI investment"]
    }
    """
  end

  defp previous_summary_to_text(nil) do
    "PREVIOUS SUMMARY:\nNo previous summary available (early cycles)."
  end

  defp previous_summary_to_text(summary) do
    """
    PREVIOUS SUMMARY (from cycle #{summary.cycle_number}):
    #{summary.full_context_summary}

    Previous evolution narrative: #{summary.evolution_narrative}
    """
  end

  defp claim_history_to_text([]), do: "No claim history available."

  defp claim_history_to_text(history) do
    mapped =
      Enum.map(history, fn entry ->
        "Cycle #{entry.cycle}: #{entry.claim}"
      end)

    Enum.join(mapped, "\n")
  end

  defp objections_to_text([]), do: "No critic objections recorded."

  defp objections_to_text(objections) do
    mapped =
      Enum.map(objections, fn obj ->
        status = if obj.accepted, do: "ACCEPTED", else: "REJECTED"

        question =
          if obj.clarifying_question do
            " (Question: #{obj.clarifying_question})"
          else
            ""
          end

        "- Cycle #{obj.cycle} [#{status}]: #{obj.objection}#{question}"
      end)

    Enum.join(mapped, "\n")
  end

  defp refinements_to_text([]), do: "No other agent refinements recorded."

  defp refinements_to_text(refinements) do
    mapped =
      Enum.map(refinements, fn ref ->
        status = if ref.accepted, do: "ACCEPTED", else: "REJECTED"
        "- Cycle #{ref.cycle} (#{ref.agent}) [#{status}]: #{ref.output}"
      end)

    Enum.join(mapped, "\n")
  end

  defp parse_summary_response(response, cycle_number) do
    case Agent.decode_json_response(response) do
      {:ok,
       %{
         "full_context_summary" => full_context,
         "evolution_narrative" => narrative,
         "addressed_objections" => addressed,
         "remaining_gaps" => gaps
       }}
      when is_binary(full_context) and is_binary(narrative) and is_list(addressed) and
             is_list(gaps) ->
        {:ok,
         %{
           full_context_summary: strip_transitional_prefix(full_context),
           evolution_narrative: narrative,
           addressed_objections: list_to_map(addressed),
           remaining_gaps: list_to_map(gaps),
           cycle_number: cycle_number
         }}

      _ ->
        {:error, :invalid_summary_response_format}
    end
  end

  # Sorted by length descending so longer matches are tried first
  @transitional_prefixes [
    "in conclusion",
    "as a result",
    "consequently",
    "accordingly",
    "ultimately",
    "therefore",
    "finally",
    "hence",
    "thus",
    "so"
  ]

  defp strip_transitional_prefix(text) when is_binary(text) do
    trimmed = String.trim(text)
    lower = String.downcase(trimmed)

    Enum.reduce_while(@transitional_prefixes, trimmed, fn prefix, acc ->
      if String.starts_with?(lower, prefix) do
        # Find the actual text after the prefix
        prefix_len = String.length(prefix)
        rest = String.slice(acc, prefix_len..-1//1)

        # Strip leading punctuation and whitespace (comma, colon, etc.)
        cleaned = String.replace(rest, ~r/^[\s,;:]+/, "")

        # Capitalize the first letter
        result =
          case String.first(cleaned) do
            nil -> cleaned
            first -> String.upcase(first) <> String.slice(cleaned, 1..-1//1)
          end

        {:halt, result}
      else
        {:cont, acc}
      end
    end)
  end

  defp strip_transitional_prefix(text), do: text

  defp list_to_map(list) do
    list
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.with_index(1)
    |> Enum.into(%{}, fn {item, idx} -> {Integer.to_string(idx), item} end)
  end

  defp broadcast_summary_updated(blackboard_id, claim_summary) do
    summary_map = %{
      blackboard_id: claim_summary.blackboard_id,
      cycle_number: claim_summary.cycle_number,
      full_context_summary: claim_summary.full_context_summary,
      evolution_narrative: claim_summary.evolution_narrative,
      addressed_objections: claim_summary.addressed_objections,
      remaining_gaps: claim_summary.remaining_gaps,
      key_transitions: claim_summary.key_transitions,
      inserted_at: claim_summary.inserted_at,
      updated_at: claim_summary.updated_at
    }

    WebPubSub.broadcast_summary_updated(blackboard_id, summary_map)
  end

  defp store_summary(blackboard_id, summary_data) do
    attrs = %{
      blackboard_id: blackboard_id,
      cycle_number: summary_data.cycle_number,
      full_context_summary: summary_data.full_context_summary,
      evolution_narrative: summary_data.evolution_narrative,
      addressed_objections: summary_data.addressed_objections,
      remaining_gaps: summary_data.remaining_gaps,
      key_transitions: %{}
    }

    # Check if summary already exists for this blackboard_id and cycle_number
    existing =
      from(cs in ClaimSummary,
        where:
          cs.blackboard_id == ^blackboard_id and cs.cycle_number == ^summary_data.cycle_number
      )
      |> Repo.one()

    case existing do
      nil ->
        # Insert new summary
        changeset = ClaimSummary.changeset(%ClaimSummary{}, attrs)

        case Repo.insert(changeset) do
          {:ok, claim_summary} -> {:ok, claim_summary}
          {:error, changeset} -> {:error, changeset}
        end

      existing_summary ->
        # Update existing summary with newer data
        changeset = ClaimSummary.changeset(existing_summary, attrs)

        case Repo.update(changeset) do
          {:ok, claim_summary} -> {:ok, claim_summary}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end
end
