defmodule UnshackledWeb.SessionsLive.Show.State do
  @moduledoc """
  Socket state builders for SessionsLive.Show.

  This module centralizes all socket assigns into visible state maps,
  making the full socket shape discoverable in one place.

  ## State Fields

  ### Core Session Data
  - `blackboard` - The BlackboardRecord struct (or nil for not-found)
  - `session_id` - The Session UUID (or nil for not-found)
  - `status` - Atom status: :running, :paused, :stopped, :completed, :graduated, :dead

  ### UI State
  - `not_found` - Boolean indicating if blackboard was found
  - `show_stop_confirm` - Boolean for stop confirmation modal
  - `show_delete_confirm` - Boolean for delete confirmation modal

  ### Session-Loaded Data (from DataLoader)
  - `support_timeline` - List of support/claim history points
  - `contributions_data` - List of agent contribution statistics
  - `cemetery_entries` - List of dead claims
  - `graduated_claims` - List of graduated claims

  ### Visualization Data
  - `trajectory_data` - Map with embedding points for 3D plot
  - `trajectory_loading` - Boolean indicating if trajectory is loading

  ### Cycle Data
  - `cycle_log` - List of cycle entries with contributions
  - `cycle_log_offset` - Current offset for pagination
  - `has_more_cycles` - Boolean indicating if more cycles exist
  - `new_cycle_number` - Integer of the newest cycle (for highlighting)

  ### Claim Tracking
  - `claim_summary` - Map with context summary, evolution narrative, etc.
  - `claim_transitions` - List of claim change records
  - `expanded_timeline_nodes` - Map of expanded timeline node IDs
  - `expanded_summary_sections` - MapSet of expanded summary section IDs

  ### Cost Data
  - `total_cost` - Float total session cost in USD
  - `cost_by_cycle` - List of cost breakdown by cycle
  - `cost_by_agent` - List of cost breakdown by agent
  """

  alias Unshackled.Costs

  @doc """
  Builds the complete socket state for a found blackboard.

  ## Parameters
  - `blackboard` - The BlackboardRecord struct
  - `session_id` - The Session UUID (may be nil)
  - `session_data` - Map with session loaded data (from load_session_data_fast/2)
  - `opts` - Keyword list of additional options:
    - `:cycle_log` - Cycle log list (default: [])
    - `:has_more_cycles` - Boolean for pagination (default: false)
    - `:claim_summary` - Claim summary map (default: nil)
    - `:claim_transitions` - List of claim transitions (default: [])
    - `:status` - Pre-determined status (optional, will be computed if not provided)

  ## Returns
  A map of all socket assigns ready for `assign/2`.

  ## Example
      iex> blackboard = %BlackboardRecord{id: 1, cycle_count: 5}
      iex> session_data = %{support_timeline: [], contributions_data: [], cemetery_entries: [], graduated_claims: []}
      iex> State.build_found_state(blackboard, "session-123", session_data, [])
      %{
        blackboard: %BlackboardRecord{...},
        session_id: "session-123",
        status: :running,
        not_found: false,
        support_timeline: [],
        ...
      }
  """
  @spec build_found_state(
          BlackboardRecord.t() | nil,
          String.t() | nil,
          map(),
          keyword()
        ) :: map()
  def build_found_state(blackboard, session_id, session_data, opts \\ []) do
    %{
      blackboard: blackboard,
      session_id: session_id,
      status: Keyword.get(opts, :status),
      not_found: false,
      show_stop_confirm: false,
      show_delete_confirm: false,
      support_timeline: Map.get(session_data, :support_timeline, []),
      contributions_data: Map.get(session_data, :contributions_data, []),
      trajectory_data: %{points: []},
      trajectory_loading: true,
      cemetery_entries: Map.get(session_data, :cemetery_entries, []),
      graduated_claims: Map.get(session_data, :graduated_claims, []),
      cycle_log: Keyword.get(opts, :cycle_log, []),
      cycle_log_offset: length(Keyword.get(opts, :cycle_log, [])),
      has_more_cycles: Keyword.get(opts, :has_more_cycles, false),
      new_cycle_number: nil,
      claim_summary: Keyword.get(opts, :claim_summary),
      claim_transitions: Keyword.get(opts, :claim_transitions, []),
      expanded_timeline_nodes: %{},
      expanded_summary_sections: MapSet.new(),
      total_cost: Costs.get_session_total_cost(blackboard.id),
      cost_by_cycle: Costs.get_cost_by_cycle(blackboard.id),
      cost_by_agent: Costs.get_cost_by_agent(blackboard.id)
    }
  end

  @doc """
  Builds default socket state for a not-found blackboard.

  All fields have safe defaults to prevent KeyError on render.

  ## Returns
  A map of all socket assigns with nil/empty defaults.

  ## Example
      iex> State.build_not_found_state()
      %{
        blackboard: nil,
        session_id: nil,
        status: nil,
        not_found: true,
        support_timeline: [],
        ...
      }
  """
  @spec build_not_found_state() :: map()
  def build_not_found_state do
    %{
      blackboard: nil,
      session_id: nil,
      status: nil,
      not_found: true,
      show_stop_confirm: false,
      show_delete_confirm: false,
      support_timeline: [],
      contributions_data: [],
      trajectory_data: %{points: []},
      trajectory_loading: false,
      cemetery_entries: [],
      graduated_claims: [],
      cycle_log: [],
      cycle_log_offset: 0,
      has_more_cycles: false,
      new_cycle_number: nil,
      claim_summary: nil,
      claim_transitions: [],
      expanded_timeline_nodes: %{},
      expanded_summary_sections: MapSet.new(),
      total_cost: 0.0,
      cost_by_cycle: [],
      cost_by_agent: []
    }
  end

  @doc """
  Builds partial socket state for refresh scenarios.

  This is used when updating socket state after new data is loaded,
  without recalculating cost data.

  ## Parameters
  - `blackboard` - The BlackboardRecord struct
  - `session_id` - The Session UUID
  - `session_data` - Map with session loaded data
  - `opts` - Keyword list of additional options:
    - `:cycle_log` - Cycle log list (default: [])
    - `:has_more_cycles` - Boolean for pagination (default: false)
    - `:new_cycle_number` - New cycle number to highlight (optional)
    - `:status` - Pre-determined status (optional)

  ## Returns
  A map of socket assigns ready for merge/assign.

  ## Example
      iex> State.build_refresh_state(blackboard, "session-123", session_data, cycle_log: log)
      %{
        blackboard: %BlackboardRecord{...},
        support_timeline: [],
        cycle_log: log,
        ...
      }
  """
  @spec build_refresh_state(
          BlackboardRecord.t(),
          String.t() | nil,
          map(),
          keyword()
        ) :: map()
  def build_refresh_state(blackboard, _session_id, session_data, opts \\ []) do
    %{
      blackboard: blackboard,
      status: Keyword.get(opts, :status),
      support_timeline: Map.get(session_data, :support_timeline, []),
      contributions_data: Map.get(session_data, :contributions_data, []),
      cemetery_entries: Map.get(session_data, :cemetery_entries, []),
      graduated_claims: Map.get(session_data, :graduated_claims, []),
      cycle_log: Keyword.get(opts, :cycle_log, []),
      cycle_log_offset: length(Keyword.get(opts, :cycle_log, [])),
      has_more_cycles: Keyword.get(opts, :has_more_cycles, false),
      new_cycle_number: Keyword.get(opts, :new_cycle_number)
    }
  end
end
