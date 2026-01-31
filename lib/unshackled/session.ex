defmodule Unshackled.Session do
  @moduledoc """
  Public API for session lifecycle management.

  This module provides functions for starting, pausing, resuming, and stopping
  reasoning sessions. Each session is managed by a separate CycleRunner process
  and has a unique session ID.

  ## PubSub Events

  This module broadcasts the following events via `UnshackledWeb.PubSub`:

  - `{:session_started, session_id, blackboard_id}` - When a new session starts
  - `{:session_paused, session_id}` - When a session is paused
  - `{:session_resumed, session_id}` - When a session is resumed
  - `{:session_stopped, session_id}` - When a session is stopped

  Subscribe to these events using `UnshackledWeb.PubSub.subscribe_session/1`
  or `UnshackledWeb.PubSub.subscribe_sessions/0`.
  """

  use GenServer
  require Logger

  alias Unshackled.Config
  alias Unshackled.Cycle.Runner
  alias UnshackledWeb.PubSub, as: WebPubSub

  @type session_id :: String.t()
  @type session_status :: :running | :paused | :completed | :stopped

  defstruct [
    :sessions,
    :next_id
  ]

  @type t :: %__MODULE__{
          sessions: %{optional(session_id()) => session_info()},
          next_id: pos_integer()
        }

  @type session_info :: %{
          pid: pid(),
          status: session_status(),
          blackboard_id: pos_integer() | nil,
          cycle_count: non_neg_integer(),
          config: Config.t()
        }

  @doc """
  Starts the Session registry.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    # Subscribe to session events to receive cycle updates from Runners
    Phoenix.PubSub.subscribe(UnshackledWeb.PubSub.pubsub_name(), "sessions")

    state = %__MODULE__{
      sessions: %{},
      next_id: 1
    }

    {:ok, state}
  end

  @doc """
  Starts a new session with the given configuration.

  Returns {:ok, session_id} on success.
  Returns {:error, reason} on failure.

  ## Examples

      iex> config = Unshackled.Config.new(seed_claim: "Test claim", max_cycles: 50)
      iex> {:ok, session_id} = Unshackled.Session.start(config)
      iex> is_binary(session_id)
      true

  """
  @spec start(Config.t()) :: {:ok, session_id()} | {:error, term()}
  def start(%Config{} = config) do
    GenServer.call(__MODULE__, {:start_session, config})
  end

  @doc """
  Pauses a running session.

  Returns :ok on success.
  Returns {:error, :not_found} if session doesn't exist.
  Returns {:error, :not_running} if session is not running.
  Returns {:error, :already_paused} if session is already paused.

  ## Examples

      iex> :ok = Unshackled.Session.pause("session_123")

  """
  @spec pause(session_id()) :: :ok | {:error, term()}
  def pause(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:pause_session, session_id})
  end

  @doc """
  Resumes a paused session.

  Returns :ok on success.
  Returns {:error, :not_found} if session doesn't exist.
  Returns {:error, :not_paused} if session is not paused.
  Returns {:error, :cannot_resume} if session cannot be resumed.

  ## Examples

      iex> :ok = Unshackled.Session.resume("session_123")

  """
  @spec resume(session_id()) :: :ok | {:error, term()}
  def resume(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:resume_session, session_id})
  end

  @doc """
  Stops a session.

  Returns :ok on success.
  Returns {:error, :not_found} if session doesn't exist.
  Returns {:error, :already_stopped} if session is already stopped.

  ## Examples

      iex> :ok = Unshackled.Session.stop("session_123")

  """
  @spec stop(session_id()) :: :ok | {:error, term()}
  def stop(session_id) when is_binary(session_id) do
    # Use a longer timeout since stopping may need to wait for LLM calls to complete
    GenServer.call(__MODULE__, {:stop_session, session_id}, 30_000)
  end

  @doc """
  Returns the status of a session.

  Returns {:ok, status} where status is :running, :paused, :completed, or :stopped.
  Returns {:error, :not_found} if session doesn't exist.

  ## Examples

      iex> {:ok, :running} = Unshackled.Session.status("session_123")

  """
  @spec status(session_id()) :: {:ok, session_status()} | {:error, :not_found}
  def status(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:get_status, session_id})
  end

  @doc """
  Returns a list of all session IDs with their status.

  ## Examples

      iex> sessions = Unshackled.Session.list_sessions()
      iex> is_list(sessions)
      true

  """
  @spec list_sessions() :: [{session_id(), session_status()}]
  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  @doc """
  Returns detailed information about a session.

  Returns {:ok, info} where info contains status, blackboard_id, cycle_count, and config.
  Returns {:error, :not_found} if session doesn't exist.

  ## Examples

      iex> {:ok, info} = Unshackled.Session.get_info("session_123")
      iex> is_map(info)
      true

  """
  @spec get_info(session_id()) :: {:ok, session_info()} | {:error, :not_found}
  def get_info(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:get_info, session_id})
  end

  @doc """
  Returns the first active (running) session if one exists.

  Returns {:ok, {session_id, session_info}} for the first running session.
  Returns {:ok, nil} if no sessions are running.

  ## Examples

      iex> {:ok, {session_id, info}} = Unshackled.Session.get_active_session()

  """
  @spec get_active_session() :: {:ok, {session_id(), session_info()} | nil}
  def get_active_session do
    GenServer.call(__MODULE__, :get_active_session)
  end

  @impl GenServer
  def handle_call({:start_session, %Config{} = config}, _from, state) do
    session_id = "session_#{String.pad_leading(Integer.to_string(state.next_id), 6, "0")}"
    opts = Config.to_keyword_list(config) ++ [session_id: session_id]

    case Runner.start_link(opts, :"#{session_id}") do
      {:ok, pid} ->
        Process.monitor(pid)

        case Runner.start_session(pid) do
          {:ok, blackboard_id} ->
            session_info = %{
              pid: pid,
              status: :running,
              blackboard_id: blackboard_id,
              cycle_count: 0,
              config: config
            }

            new_sessions = Map.put(state.sessions, session_id, session_info)
            new_state = %{state | sessions: new_sessions, next_id: state.next_id + 1}

            Logger.info("Session started: #{session_id}")
            WebPubSub.broadcast_session_started(session_id, blackboard_id)
            {:reply, {:ok, session_id}, new_state}

          {:error, reason} ->
            GenServer.stop(pid)
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:pause_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: :paused} ->
        {:reply, {:error, :already_paused}, state}

      %{status: :completed} ->
        {:reply, {:error, :cannot_pause_completed}, state}

      %{status: :stopped} ->
        {:reply, {:error, :cannot_pause_stopped}, state}

      %{status: :running} = session_info ->
        # Session is running, pause it (no need to check Runner - we trust our cached status)
        new_session_info = %{session_info | status: :paused}
        new_sessions = Map.put(state.sessions, session_id, new_session_info)

        Logger.info("Session paused: #{session_id}")
        WebPubSub.broadcast_session_paused(session_id)
        {:reply, :ok, %{state | sessions: new_sessions}}
    end
  end

  @impl GenServer
  def handle_call({:resume_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: :running} ->
        {:reply, {:error, :not_paused}, state}

      %{status: :completed} ->
        {:reply, {:error, :cannot_resume_completed}, state}

      %{status: :stopped} ->
        {:reply, {:error, :cannot_resume_stopped}, state}

      %{cycle_count: cycle_count} = session_info ->
        # Use cached cycle_count instead of blocking call to Runner
        max_cycles = session_info.config.max_cycles

        if cycle_count >= max_cycles do
          new_session_info = %{session_info | status: :completed}
          new_sessions = Map.put(state.sessions, session_id, new_session_info)

          Logger.info("Session already completed: #{session_id}")
          {:reply, {:error, :already_completed}, %{state | sessions: new_sessions}}
        else
          send(session_info.pid, :run_cycle)
          new_session_info = %{session_info | status: :running}
          new_sessions = Map.put(state.sessions, session_id, new_session_info)

          Logger.info("Session resumed: #{session_id}")
          WebPubSub.broadcast_session_resumed(session_id)
          {:reply, :ok, %{state | sessions: new_sessions}}
        end
    end
  end

  @impl GenServer
  def handle_call({:stop_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: :stopped} ->
        {:reply, {:error, :already_stopped}, state}

      %{pid: pid} = session_info ->
        # Use a timeout for GenServer.stop to avoid blocking indefinitely
        # If the runner is mid-LLM call, give it time but don't wait forever
        try do
          GenServer.stop(pid, :normal, 25_000)
        catch
          :exit, {:timeout, _} ->
            # If timeout, force kill the process
            Logger.warning("Session #{session_id} stop timed out, forcing termination")
            Process.exit(pid, :kill)

          :exit, {:noproc, _} ->
            # Process already dead, that's fine
            :ok
        end

        new_session_info = %{session_info | status: :stopped}
        new_sessions = Map.put(state.sessions, session_id, new_session_info)

        Logger.info("Session stopped: #{session_id}")
        WebPubSub.broadcast_session_stopped(session_id)
        {:reply, :ok, %{state | sessions: new_sessions}}
    end
  end

  @impl GenServer
  def handle_call({:get_status, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: :running, cycle_count: cycle_count, config: config} = session_info ->
        # Use cached cycle_count instead of blocking call to Runner
        max_cycles = config.max_cycles

        if cycle_count >= max_cycles do
          new_session_info = %{session_info | status: :completed}
          new_sessions = Map.put(state.sessions, session_id, new_session_info)

          {:reply, {:ok, :completed}, %{state | sessions: new_sessions}}
        else
          {:reply, {:ok, :running}, state}
        end

      %{status: status} ->
        {:reply, {:ok, status}, state}
    end
  end

  @impl GenServer
  def handle_call(:list_sessions, _from, state) do
    sessions =
      state.sessions
      |> Enum.map(fn {id, info} -> {id, info.status} end)
      |> Enum.sort_by(fn {id, _status} -> id end)

    {:reply, sessions, state}
  end

  @impl GenServer
  def handle_call({:get_info, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      session_info ->
        {:reply, {:ok, session_info}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_active_session, _from, state) do
    active = Enum.find(state.sessions, fn {_id, info} -> info.status == :running end)
    {:reply, {:ok, active}, state}
  end

  @impl GenServer
  def handle_info({:cycle_complete, session_id, cycle_data}, state) do
    # Update cached cycle_count when Runner broadcasts cycle completion
    case Map.get(state.sessions, session_id) do
      nil ->
        {:noreply, state}

      session_info ->
        new_cycle_count = cycle_data.cycle_number + 1
        new_session_info = %{session_info | cycle_count: new_cycle_count}

        # Check if session completed
        new_session_info =
          if new_cycle_count >= session_info.config.max_cycles do
            %{new_session_info | status: :completed}
          else
            new_session_info
          end

        new_sessions = Map.put(state.sessions, session_id, new_session_info)
        {:noreply, %{state | sessions: new_sessions}}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    sessions =
      Enum.map(state.sessions, fn {id, info} ->
        if info.pid == pid do
          Logger.warning("Session process #{id} exited: #{inspect(reason)}")
          {id, %{info | status: :stopped}}
        else
          {id, info}
        end
      end)
      |> Map.new()

    {:noreply, %{state | sessions: sessions}}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    # Ignore other PubSub messages (session_started, session_paused, etc.)
    {:noreply, state}
  end

  @doc """
  Handles GenServer termination and cleanup.

  Logs the shutdown reason along with the count of active sessions at shutdown time.
  For normal shutdowns, logs an informational message. For crash reasons, logs at
  warning level with full reason details.

  ## Examples

      # Normal shutdown logs:
      # "Shutting down Session with reason: :normal (3 active sessions)"

      # Crash shutdown logs:
      # "Session terminating with reason: {:error, :killed} (5 active sessions)"

  """
  @impl GenServer
  @spec terminate(term(), t()) :: :ok
  def terminate(reason, state) do
    active_count =
      state.sessions
      |> Enum.count(fn {_id, info} -> info.status == :running end)

    case reason do
      :normal ->
        Logger.info(
          "Shutting down Session with reason: :normal (#{active_count} active sessions)"
        )

      :shutdown ->
        Logger.info(
          "Shutting down Session with reason: :shutdown (#{active_count} active sessions)"
        )

      {:shutdown, _} = shutdown_reason ->
        Logger.info(
          "Shutting down Session with reason: #{inspect(shutdown_reason)} (#{active_count} active sessions)"
        )

      other_reason ->
        Logger.warning(
          "Session terminating with reason: #{inspect(other_reason)} (#{active_count} active sessions)"
        )
    end

    :ok
  end
end
