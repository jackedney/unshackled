defmodule UnshackledWeb.SessionsLive.Show.DataLoader do
  @moduledoc """
  Data loading functions for SessionsLive.Show.
  Isolates database query logic from LiveView for better testability.
  """
  import Ecto.Query

  alias Unshackled.Agents.AgentContribution
  alias Unshackled.Agents.Summarizer
  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Blackboard.CemeteryEntry
  alias Unshackled.Blackboard.Server
  alias Unshackled.Evolution.ClaimTransition
  alias Unshackled.Embedding.TrajectoryPoint
  alias Unshackled.Repo
  alias Unshackled.Visualization.Trajectory

  @doc """
  Loads a blackboard by ID.
  Returns {:ok, blackboard} or {:error, :not_found}.
  """
  @spec load_blackboard(integer()) :: {:ok, BlackboardRecord} | {:error, :not_found}
  def load_blackboard(id) do
    case Repo.get(BlackboardRecord, id) do
      nil -> {:error, :not_found}
      blackboard -> {:ok, blackboard}
    end
  end

  @doc """
  Loads support timeline data for a blackboard.
  Returns a list of maps with cycle, support, and claim_text.
  """
  @spec load_support_timeline(integer()) :: [map()]
  def load_support_timeline(blackboard_id) do
    TrajectoryPoint
    |> where([t], t.blackboard_id == ^blackboard_id)
    |> order_by([t], asc: t.cycle_number)
    |> select([t], %{cycle: t.cycle_number, support: t.support_strength, claim_text: t.claim_text})
    |> Repo.all()
  end

  @doc """
  Loads agent contributions data for a blackboard.
  Returns a list of maps with role, count, and color.
  """
  @spec load_contributions_data(integer()) :: [map()]
  def load_contributions_data(blackboard_id) do
    AgentContribution
    |> where([c], c.blackboard_id == ^blackboard_id and c.accepted == true)
    |> group_by([c], c.agent_role)
    |> select([c], %{role: c.agent_role, count: count(c.id)})
    |> Repo.all()
    |> Enum.map(fn %{role: role, count: count} ->
      color = Unshackled.Agents.Metadata.color(role) || "#ffffff"
      %{role: role, count: count, color: color}
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  @doc """
  Loads trajectory data for a blackboard.
  Computes 3D t-SNE plot for embedding visualization.
  Returns map with points list or empty map on error.
  """
  @spec load_trajectory_data(integer()) :: map()
  def load_trajectory_data(blackboard_id) do
    trajectory_points =
      TrajectoryPoint
      |> where([t], t.blackboard_id == ^blackboard_id)
      |> order_by([t], asc: t.cycle_number)
      |> Repo.all()

    case Trajectory.plot_3d(trajectory_points, blackboard_id) do
      {:ok, data} -> data
      {:error, _reason} -> %{points: []}
    end
  end

  @doc """
  Loads cemetery entries for a blackboard.
  Returns a list of dead claims ordered by cycle_killed (most recent first).
  """
  @spec load_cemetery_entries(integer()) :: [CemeteryEntry]
  def load_cemetery_entries(blackboard_id) do
    CemeteryEntry
    |> where([c], c.blackboard_id == ^blackboard_id)
    |> order_by([c], desc: c.cycle_killed)
    |> Repo.all()
  end

  @doc """
  Loads graduated claims for a session.
  Graduated claims are stored in-memory in the Blackboard GenServer.
  Returns list of graduated claims or empty list if session is not running.
  """
  @spec load_graduated_claims(String.t() | nil) :: [map()]
  def load_graduated_claims(nil), do: []

  def load_graduated_claims(session_id) do
    Server.get_graduated(session_id)
  rescue
    _error -> []
  catch
    :exit, _ -> []
  end

  @doc """
  Loads cycle log data for displaying cycle history.
  Returns {cycle_entries, has_more} where cycle_entries is grouped by cycle number
  in reverse chronological order (most recent first).
  """
  @spec load_cycle_log(integer(), integer(), integer()) :: {[map()], boolean()}
  def load_cycle_log(blackboard_id, offset, limit) do
    cycle_numbers = fetch_cycle_numbers(blackboard_id)
    {cycles_to_fetch, has_more} = paginate_cycles(cycle_numbers, offset, limit)
    cycle_entries = build_cycle_entries(blackboard_id, cycles_to_fetch)
    {cycle_entries, has_more}
  end

  @doc """
  Fetches all cycle numbers for a blackboard.
  Returns sorted list of cycle numbers in descending order.
  """
  @spec fetch_cycle_numbers(integer()) :: [integer()]
  def fetch_cycle_numbers(blackboard_id) do
    AgentContribution
    |> where([c], c.blackboard_id == ^blackboard_id)
    |> group_by([c], c.cycle_number)
    |> select([c], c.cycle_number)
    |> Repo.all()
    |> Enum.sort(:desc)
  end

  @doc """
  Paginates cycle numbers for pagination.
  Returns {paginated_cycles, has_more} tuple.
  """
  @spec paginate_cycles([integer()], integer(), integer()) :: {[integer()], boolean()}
  def paginate_cycles(cycle_numbers, offset, limit) do
    paginated =
      cycle_numbers
      |> Enum.drop(offset)
      |> Enum.take(limit + 1)

    has_more = length(paginated) > limit
    {Enum.take(paginated, limit), has_more}
  end

  @doc """
  Builds cycle entries from fetched cycle numbers.
  Returns list of cycle entry maps with contributions and metadata.
  """
  @spec build_cycle_entries(integer(), [integer()]) :: [map()]
  def build_cycle_entries(_blackboard_id, []), do: []

  def build_cycle_entries(blackboard_id, cycles_to_fetch) do
    contributions = fetch_contributions_for_cycles(blackboard_id, cycles_to_fetch)
    grouped = Enum.group_by(contributions, & &1.cycle_number)
    Enum.map(cycles_to_fetch, &build_cycle_entry(&1, grouped))
  end

  @doc """
  Fetches contributions for specific cycles.
  Returns list of AgentContribution records ordered by cycle number and inserted_at.
  """
  @spec fetch_contributions_for_cycles(integer(), [integer()]) :: [AgentContribution.t()]
  def fetch_contributions_for_cycles(blackboard_id, cycles) do
    AgentContribution
    |> where([c], c.blackboard_id == ^blackboard_id and c.cycle_number in ^cycles)
    |> order_by([c], desc: c.cycle_number, asc: c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Builds a single cycle entry from cycle number and grouped contributions.
  Returns map with cycle_number, contributions, total_delta, and inserted_at.
  """
  @spec build_cycle_entry(integer(), %{integer() => [AgentContribution.t()]}) :: map()
  def build_cycle_entry(cycle_num, grouped) do
    cycle_contributions = Map.get(grouped, cycle_num, [])

    %{
      cycle_number: cycle_num,
      contributions: Enum.map(cycle_contributions, &contribution_to_map/1),
      total_delta: calculate_total_delta(cycle_contributions),
      inserted_at:
        case cycle_contributions do
          [first | _] -> first.inserted_at
          _ -> nil
        end
    }
  end

  @doc """
  Converts an AgentContribution to a map.
  Returns map with agent_role, support_delta, accepted, and output_text.
  """
  @spec contribution_to_map(AgentContribution.t()) :: map()
  def contribution_to_map(c) do
    %{
      agent_role: c.agent_role,
      support_delta: c.support_delta,
      accepted: c.accepted,
      output_text: c.output_text
    }
  end

  @doc """
  Calculates total delta from a list of contributions.
  Sums support_delta from accepted contributions only.
  """
  @spec calculate_total_delta([AgentContribution.t()]) :: float()
  def calculate_total_delta(contributions) do
    contributions
    |> Enum.filter(& &1.accepted)
    |> Enum.map(& &1.support_delta)
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
  end

  @doc """
  Loads claim transitions for a blackboard.
  Returns list of transitions with trigger_contribution associations.
  """
  @spec load_claim_transitions(integer()) :: [ClaimTransition.t()]
  def load_claim_transitions(blackboard_id) do
    transitions =
      ClaimTransition
      |> where([ct], ct.blackboard_id == ^blackboard_id)
      |> order_by([ct], asc: ct.to_cycle)
      |> Repo.all()

    contributions =
      AgentContribution
      |> where([ac], ac.blackboard_id == ^blackboard_id)
      |> Repo.all()
      |> Enum.reduce(%{}, fn ac, acc ->
        Map.put(acc, ac.id, ac)
      end)

    transitions
    |> Enum.map(fn transition ->
      contribution = Map.get(contributions, transition.trigger_contribution_id)
      Map.put(transition, :trigger_contribution, contribution)
    end)
  end

  @doc """
  Loads the latest claim summary for a blackboard.
  Returns summary map or nil if not found.
  """
  @spec load_claim_summary(integer(), integer()) :: map() | nil
  def load_claim_summary(blackboard_id, _current_cycle_count) do
    case Summarizer.get_latest_summary(blackboard_id) do
      {:ok, summary} ->
        summary

      {:error, :not_found} ->
        nil
    end
  end

  @doc """
  Loads session data fast (excluding trajectory which loads asynchronously).
  Returns map with support_timeline, contributions_data, cemetery_entries, and graduated_claims.
  """
  @spec load_session_data_fast(integer(), String.t() | nil) :: map()
  def load_session_data_fast(blackboard_id, session_id) do
    %{
      support_timeline: load_support_timeline(blackboard_id),
      contributions_data: load_contributions_data(blackboard_id),
      cemetery_entries: load_cemetery_entries(blackboard_id),
      graduated_claims: load_graduated_claims(session_id)
    }
  end

  @doc """
  Gets support strength at a specific cycle.
  Returns support value or nil if not found.
  """
  @spec get_support_at_cycle(integer(), integer()) :: float() | nil
  def get_support_at_cycle(blackboard_id, cycle_number) do
    query =
      from(tp in TrajectoryPoint,
        where: tp.blackboard_id == ^blackboard_id and tp.cycle_number == ^cycle_number,
        select: tp.support_strength,
        limit: 1
      )

    Repo.one(query)
  end

  @doc """
  Formats support level for a specific cycle.
  Returns formatted string like "75.0%" or "N/A" if not found.
  """
  @spec format_support_level(integer(), integer()) :: String.t()
  def format_support_level(blackboard_id, cycle_number) do
    case get_support_at_cycle(blackboard_id, cycle_number) do
      nil -> "N/A"
      support -> "#{Float.round(support * 100, 1)}%"
    end
  end
end
