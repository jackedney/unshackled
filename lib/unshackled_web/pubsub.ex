defmodule UnshackledWeb.PubSub do
  @moduledoc """
  Helper functions for PubSub broadcasting in the Unshackled web application.

  Provides a centralized interface for broadcasting session events to LiveViews.
  All broadcasts use the `Unshackled.PubSub` server configured in the application.

  ## Topic Naming

  - `"session:<session_id>"` - Session-specific updates (cycles, state changes)
  - `"sessions"` - Global session list updates (new sessions, status changes)
  - `"blackboard:<blackboard_id>"` - Blackboard-specific updates (claim evolution, summaries)

  ## Event Types

  Session lifecycle:
  - `{:session_started, session_id, blackboard_id}` - New session started
  - `{:session_paused, session_id}` - Session paused
  - `{:session_resumed, session_id}` - Session resumed
  - `{:session_stopped, session_id}` - Session stopped
  - `{:session_completed, session_id}` - Session reached max cycles

  Cycle events:
  - `{:cycle_started, cycle_data}` - Cycle began execution
  - `{:cycle_complete, cycle_data}` - Cycle finished execution

  Blackboard state:
  - `{:blackboard_updated, blackboard_state}` - State changed
  - `{:claim_updated, new_claim}` - Current claim changed
  - `{:support_updated, new_support}` - Support strength changed
  - `{:claim_died, cemetery_entry}` - Claim killed
  - `{:claim_graduated, graduated_entry}` - Claim graduated

  Claim evolution:
  - `{:claim_changed, blackboard_id, transition}` - Claim evolved with transition data
  - `{:summary_updated, blackboard_id, summary}` - Context summary generated

  Cost events:
  - `{:cost_recorded, session_id, blackboard_id, cost_data}` - Cost recorded for session
  """

  @pubsub Unshackled.PubSub

  @type session_id :: String.t()
  @type blackboard_id :: pos_integer()

  @doc """
  Returns the PubSub server name for direct subscriptions.
  """
  @spec pubsub_name() :: atom()
  def pubsub_name, do: @pubsub

  # Topic helpers

  @doc """
  Returns the topic for a specific session.
  """
  @spec session_topic(session_id()) :: String.t()
  def session_topic(session_id) when is_binary(session_id) do
    "session:#{session_id}"
  end

  @doc """
  Returns the topic for global session list updates.
  """
  @spec sessions_topic() :: String.t()
  def sessions_topic, do: "sessions"

  @doc """
  Returns the topic for a specific blackboard's evolution updates.
  """
  @spec blackboard_topic(blackboard_id()) :: String.t()
  def blackboard_topic(blackboard_id) when is_integer(blackboard_id) do
    "blackboard:#{blackboard_id}"
  end

  # Subscription helpers

  @doc """
  Subscribes the calling process to a session's updates.
  """
  @spec subscribe_session(session_id()) :: :ok | {:error, term()}
  def subscribe_session(session_id) when is_binary(session_id) do
    Phoenix.PubSub.subscribe(@pubsub, session_topic(session_id))
  end

  @doc """
  Subscribes the calling process to global session list updates.
  """
  @spec subscribe_sessions() :: :ok | {:error, term()}
  def subscribe_sessions do
    Phoenix.PubSub.subscribe(@pubsub, sessions_topic())
  end

  @doc """
  Unsubscribes the calling process from a session's updates.
  """
  @spec unsubscribe_session(session_id()) :: :ok
  def unsubscribe_session(session_id) when is_binary(session_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, session_topic(session_id))
  end

  @doc """
  Unsubscribes the calling process from global session list updates.
  """
  @spec unsubscribe_sessions() :: :ok
  def unsubscribe_sessions do
    Phoenix.PubSub.unsubscribe(@pubsub, sessions_topic())
  end

  @doc """
  Subscribes the calling process to a blackboard's evolution updates.
  """
  @spec subscribe_blackboard(blackboard_id()) :: :ok | {:error, term()}
  def subscribe_blackboard(blackboard_id) when is_integer(blackboard_id) do
    Phoenix.PubSub.subscribe(@pubsub, blackboard_topic(blackboard_id))
  end

  @doc """
  Unsubscribes the calling process from a blackboard's evolution updates.
  """
  @spec unsubscribe_blackboard(blackboard_id()) :: :ok
  def unsubscribe_blackboard(blackboard_id) when is_integer(blackboard_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, blackboard_topic(blackboard_id))
  end

  # Session lifecycle broadcasts

  @doc """
  Broadcasts that a new session has started.
  """
  @spec broadcast_session_started(session_id(), blackboard_id()) :: :ok | {:error, term()}
  def broadcast_session_started(session_id, blackboard_id)
      when is_binary(session_id) and is_integer(blackboard_id) do
    broadcast_to_sessions({:session_started, session_id, blackboard_id})
    broadcast_to_session(session_id, {:session_started, session_id, blackboard_id})
  end

  @doc """
  Broadcasts that a session has been paused.
  """
  @spec broadcast_session_paused(session_id()) :: :ok | {:error, term()}
  def broadcast_session_paused(session_id) when is_binary(session_id) do
    broadcast_to_sessions({:session_paused, session_id})
    broadcast_to_session(session_id, {:session_paused, session_id})
  end

  @doc """
  Broadcasts that a session has been resumed.
  """
  @spec broadcast_session_resumed(session_id()) :: :ok | {:error, term()}
  def broadcast_session_resumed(session_id) when is_binary(session_id) do
    broadcast_to_sessions({:session_resumed, session_id})
    broadcast_to_session(session_id, {:session_resumed, session_id})
  end

  @doc """
  Broadcasts that a session has been stopped.
  """
  @spec broadcast_session_stopped(session_id()) :: :ok | {:error, term()}
  def broadcast_session_stopped(session_id) when is_binary(session_id) do
    broadcast_to_sessions({:session_stopped, session_id})
    broadcast_to_session(session_id, {:session_stopped, session_id})
  end

  @doc """
  Broadcasts that a session has completed (reached max cycles).
  """
  @spec broadcast_session_completed(session_id()) :: :ok | {:error, term()}
  def broadcast_session_completed(session_id) when is_binary(session_id) do
    broadcast_to_sessions({:session_completed, session_id})
    broadcast_to_session(session_id, {:session_completed, session_id})
  end

  # Cycle broadcasts

  @doc """
  Broadcasts that a cycle has started.

  ## Cycle Data

  The cycle_data map should include:
  - `:session_id` - The session identifier
  - `:cycle_number` - The current cycle number
  - `:blackboard_id` - The blackboard record ID
  """
  @spec broadcast_cycle_started(session_id(), map()) :: :ok | {:error, term()}
  def broadcast_cycle_started(session_id, cycle_data)
      when is_binary(session_id) and is_map(cycle_data) do
    broadcast_to_session(session_id, {:cycle_started, cycle_data})
  end

  @doc """
  Broadcasts that a cycle has completed.

  ## Cycle Data

  The cycle_data map should include:
  - `:session_id` - The session identifier
  - `:cycle_number` - The completed cycle number
  - `:blackboard_id` - The blackboard record ID
  - `:duration_ms` - How long the cycle took
  - `:support_strength` - Current support after cycle
  - `:current_claim` - Current claim text (truncated)
  """
  @spec broadcast_cycle_complete(session_id(), map()) :: :ok | {:error, term()}
  def broadcast_cycle_complete(session_id, cycle_data)
      when is_binary(session_id) and is_map(cycle_data) do
    # Broadcast to session-specific topic for LiveViews
    broadcast_to_session(session_id, {:cycle_complete, cycle_data})
    # Broadcast to sessions topic for Session GenServer to update cached cycle_count
    broadcast_to_sessions({:cycle_complete, session_id, cycle_data})
  end

  # Blackboard state broadcasts

  @doc """
  Broadcasts a full blackboard state update.
  """
  @spec broadcast_blackboard_updated(session_id(), map()) :: :ok | {:error, term()}
  def broadcast_blackboard_updated(session_id, blackboard_state)
      when is_binary(session_id) and is_map(blackboard_state) do
    broadcast_to_session(session_id, {:blackboard_updated, blackboard_state})
  end

  @doc """
  Broadcasts that the current claim has been updated.
  """
  @spec broadcast_claim_updated(session_id(), String.t()) :: :ok | {:error, term()}
  def broadcast_claim_updated(session_id, new_claim)
      when is_binary(session_id) and is_binary(new_claim) do
    broadcast_to_session(session_id, {:claim_updated, new_claim})
  end

  @doc """
  Broadcasts that support strength has been updated.
  """
  @spec broadcast_support_updated(session_id(), float()) :: :ok | {:error, term()}
  def broadcast_support_updated(session_id, new_support)
      when is_binary(session_id) and is_number(new_support) do
    broadcast_to_session(session_id, {:support_updated, new_support})
  end

  @doc """
  Broadcasts that a claim has died and been added to the cemetery.
  """
  @spec broadcast_claim_died(session_id(), map()) :: :ok | {:error, term()}
  def broadcast_claim_died(session_id, cemetery_entry)
      when is_binary(session_id) and is_map(cemetery_entry) do
    broadcast_to_session(session_id, {:claim_died, cemetery_entry})
  end

  @doc """
  Broadcasts that a claim has graduated.
  """
  @spec broadcast_claim_graduated(session_id(), map()) :: :ok | {:error, term()}
  def broadcast_claim_graduated(session_id, graduated_entry)
      when is_binary(session_id) and is_map(graduated_entry) do
    broadcast_to_session(session_id, {:claim_graduated, graduated_entry})
  end

  # Claim evolution broadcasts

  @doc """
  Broadcasts that a claim has changed with full transition data.

  ## Transition Data

  The transition map should include:
  - `:blackboard_id` - The blackboard record ID
  - `:from_cycle` - The cycle number before the change
  - `:to_cycle` - The cycle number of the change
  - `:previous_claim` - The claim text before the change
  - `:new_claim` - The claim text after the change
  - `:trigger_agent` - The agent role that triggered the change
  - `:change_type` - The type of change (refinement, pivot, expansion, contraction)
  - `:diff_additions` - Concepts that were added
  - `:diff_removals` - Concepts that were removed
  """
  @spec broadcast_claim_changed(session_id(), map()) :: :ok | {:error, term()}
  def broadcast_claim_changed(session_id, transition)
      when is_binary(session_id) and is_map(transition) do
    broadcast_to_session(session_id, {:claim_changed, transition.blackboard_id, transition})
  end

  @doc """
  Broadcasts that a context summary has been generated.

  ## Summary Data

  The summary map should include:
  - `:blackboard_id` - The blackboard record ID
  - `:cycle_number` - The cycle number for the summary
  - `:full_context_summary` - The claim with implicit references resolved
  - `:evolution_narrative` - Brief narrative of claim evolution
  - `:addressed_objections` - List of objections addressed
  - `:remaining_gaps` - List of remaining ambiguities
  """
  @spec broadcast_summary_updated(blackboard_id(), map()) :: :ok | {:error, term()}
  def broadcast_summary_updated(blackboard_id, summary)
      when is_integer(blackboard_id) and is_map(summary) do
    broadcast_to_blackboard(blackboard_id, {:summary_updated, blackboard_id, summary})
  end

  @doc """
  Broadcasts that a cost has been recorded for a session.

  ## Cost Data

  The cost_data map should include:
  - `:blackboard_id` - The blackboard record ID
  - `:total_cost` - New total cost after recording
  - `:latest_cost_entry` - Map of the latest cost record
  """
  @spec broadcast_cost_recorded(session_id(), blackboard_id(), map()) :: :ok | {:error, term()}
  def broadcast_cost_recorded(session_id, blackboard_id, cost_data)
      when is_binary(session_id) and is_integer(blackboard_id) and is_map(cost_data) do
    broadcast_to_session(session_id, {:cost_recorded, session_id, blackboard_id, cost_data})
    broadcast_to_blackboard(blackboard_id, {:cost_recorded, session_id, blackboard_id, cost_data})
  end

  # Private broadcast helpers

  @spec broadcast_to_session(session_id(), term()) :: :ok | {:error, term()}
  defp broadcast_to_session(session_id, message) do
    Phoenix.PubSub.broadcast(@pubsub, session_topic(session_id), message)
  end

  @spec broadcast_to_sessions(term()) :: :ok | {:error, term()}
  defp broadcast_to_sessions(message) do
    Phoenix.PubSub.broadcast(@pubsub, sessions_topic(), message)
  end

  @spec broadcast_to_blackboard(blackboard_id(), term()) :: :ok | {:error, term()}
  defp broadcast_to_blackboard(blackboard_id, message) do
    Phoenix.PubSub.broadcast(@pubsub, blackboard_topic(blackboard_id), message)
  end
end
