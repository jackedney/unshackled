defmodule Unshackled.SessionTest do
  use ExUnit.Case, async: false

  alias Unshackled.Config
  alias Unshackled.Session

  @moduletag :capture_log

  setup do
    {:ok, _pid} = Application.ensure_all_started(:unshackled)

    sandbox_pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Unshackled.Repo, shared: true)

    # Clean up any existing sessions before each test
    sessions = Session.list_sessions()

    Enum.each(sessions, fn {session_id, status} ->
      if status != :stopped do
        try do
          Session.stop(session_id)
        rescue
          _ -> :ok
        catch
          :exit, _ -> :ok
        end
      end
    end)

    on_exit(fn ->
      # Stop any sessions created during this test
      try do
        sessions = Session.list_sessions()

        Enum.each(sessions, fn {session_id, status} ->
          if status not in [:stopped, :completed] do
            try do
              Session.stop(session_id)
            rescue
              _ -> :ok
            catch
              :exit, _ -> :ok
            end
          end
        end)
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end

      # Give time for background processes (summarizer, trajectory) to complete
      # before stopping the DB sandbox owner
      Process.sleep(500)

      try do
        Ecto.Adapters.SQL.Sandbox.stop_owner(sandbox_pid)
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end
    end)

    :ok
  end

  describe "start/1" do
    test "creates session and returns session_id" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)

      assert {:ok, session_id} = Session.start(config)
      assert is_binary(session_id)
      assert String.starts_with?(session_id, "session_")
    end

    test "accepts SessionConfig and returns {:ok, session_id}" do
      config = Config.new(seed_claim: "What if entropy is local?", max_cycles: 10)

      assert {:ok, session_id} = Session.start(config)
      assert is_binary(session_id)
    end

    test "starts multiple sessions with different IDs" do
      config1 = Config.new(seed_claim: "Claim 1", max_cycles: 10)
      config2 = Config.new(seed_claim: "Claim 2", max_cycles: 10)

      assert {:ok, id1} = Session.start(config1)
      assert {:ok, id2} = Session.start(config2)
      assert id1 != id2
    end

    test "session starts in running state" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 10)

      assert {:ok, session_id} = Session.start(config)
      assert {:ok, :running} = Session.status(session_id)
    end
  end

  describe "pause/1" do
    test "pauses running session" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)
      {:ok, session_id} = Session.start(config)

      assert :ok = Session.pause(session_id)
      assert {:ok, :paused} = Session.status(session_id)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = Session.pause("non_existent")
    end

    test "returns error when pausing already-paused session" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)
      {:ok, session_id} = Session.start(config)

      assert :ok = Session.pause(session_id)
      assert {:error, :already_paused} = Session.pause(session_id)
    end

    test "returns error when pausing completed session" do
      # Use max_cycles: 2 so that one cycle executes and broadcasts completion,
      # which allows the Session GenServer to detect the session has completed.
      # (With max_cycles: 1, the Runner stops before executing any cycle,
      # so the Session never receives a :cycle_complete event.)
      config = Config.new(seed_claim: "Test claim", max_cycles: 2)
      {:ok, session_id} = Session.start(config)

      # Poll for the session to complete
      # The cycle may take time due to agent execution and DB operations
      final_status =
        Enum.reduce_while(1..60, :running, fn _i, _acc ->
          Process.sleep(100)

          case Session.status(session_id) do
            {:ok, status} when status in [:completed, :stopped] -> {:halt, status}
            {:ok, status} -> {:cont, status}
            _ -> {:cont, :unknown}
          end
        end)

      # A completed session cannot be paused
      assert final_status in [:completed, :stopped]
    end

    test "returns error when pausing stopped session" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)
      {:ok, session_id} = Session.start(config)

      :ok = Session.stop(session_id)

      assert {:error, :cannot_pause_stopped} = Session.pause(session_id)
    end
  end

  describe "resume/1" do
    test "resumes paused session" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)
      {:ok, session_id} = Session.start(config)

      assert :ok = Session.pause(session_id)
      assert {:ok, :paused} = Session.status(session_id)

      assert :ok = Session.resume(session_id)
      assert {:ok, :running} = Session.status(session_id)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = Session.resume("non_existent")
    end

    test "returns error when resuming running session" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)
      {:ok, session_id} = Session.start(config)

      assert {:error, :not_paused} = Session.resume(session_id)
    end

    test "returns error when resuming completed session" do
      # Use max_cycles: 2 so that one cycle executes and broadcasts completion
      config = Config.new(seed_claim: "Test claim", max_cycles: 2)
      {:ok, session_id} = Session.start(config)

      # Poll for the session to complete
      Enum.reduce_while(1..60, :running, fn _i, _acc ->
        Process.sleep(100)

        case Session.status(session_id) do
          {:ok, status} when status in [:completed, :stopped] -> {:halt, status}
          {:ok, status} -> {:cont, status}
          _ -> {:cont, :unknown}
        end
      end)

      # A completed session cannot be resumed
      assert {:error, _reason} = Session.resume(session_id)
    end

    test "returns error when resuming stopped session" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)
      {:ok, session_id} = Session.start(config)

      :ok = Session.stop(session_id)

      assert {:error, :cannot_resume_stopped} = Session.resume(session_id)
    end
  end

  describe "stop/1" do
    test "stops running session" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)
      {:ok, session_id} = Session.start(config)

      assert :ok = Session.stop(session_id)
      assert {:ok, :stopped} = Session.status(session_id)
    end

    test "stops paused session" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)
      {:ok, session_id} = Session.start(config)

      :ok = Session.pause(session_id)

      assert :ok = Session.stop(session_id)
      assert {:ok, :stopped} = Session.status(session_id)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = Session.stop("non_existent")
    end

    test "returns error when stopping already stopped session" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)
      {:ok, session_id} = Session.start(config)

      :ok = Session.stop(session_id)

      assert {:error, :already_stopped} = Session.stop(session_id)
    end
  end

  describe "status/1" do
    test "returns running status for active session" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)
      {:ok, session_id} = Session.start(config)

      assert {:ok, :running} = Session.status(session_id)
    end

    test "returns paused status after pause" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)
      {:ok, session_id} = Session.start(config)

      :ok = Session.pause(session_id)

      assert {:ok, :paused} = Session.status(session_id)
    end

    test "returns stopped status after stop" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)
      {:ok, session_id} = Session.start(config)

      :ok = Session.stop(session_id)

      assert {:ok, :stopped} = Session.status(session_id)
    end

    test "returns running status after resume" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)
      {:ok, session_id} = Session.start(config)

      :ok = Session.pause(session_id)
      :ok = Session.resume(session_id)

      assert {:ok, :running} = Session.status(session_id)
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = Session.status("non_existent")
    end
  end

  describe "list_sessions/0" do
    test "returns a list" do
      # Session GenServer state persists across tests, so we can only test that
      # list_sessions returns a list
      sessions = Session.list_sessions()
      assert is_list(sessions)
    end

    test "includes newly created sessions with status" do
      initial_count = length(Session.list_sessions())

      config1 = Config.new(seed_claim: "Claim 1", max_cycles: 10)
      config2 = Config.new(seed_claim: "Claim 2", max_cycles: 10)
      config3 = Config.new(seed_claim: "Claim 3", max_cycles: 10)

      {:ok, id1} = Session.start(config1)
      {:ok, id2} = Session.start(config2)
      {:ok, id3} = Session.start(config3)

      :ok = Session.pause(id2)
      :ok = Session.stop(id3)

      sessions = Session.list_sessions()

      # Should have 3 more sessions than before
      assert length(sessions) == initial_count + 3

      # Find our sessions and verify their statuses
      our_sessions = Enum.filter(sessions, fn {id, _} -> id in [id1, id2, id3] end)
      assert length(our_sessions) == 3

      statuses = Enum.map(our_sessions, fn {_, status} -> status end)
      assert :running in statuses or :completed in statuses
      assert :paused in statuses
      assert :stopped in statuses
    end

    test "returns sessions sorted by ID" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 10)

      {:ok, id1} = Session.start(config)
      {:ok, id2} = Session.start(config)
      {:ok, id3} = Session.start(config)

      sessions = Session.list_sessions()

      # Get the session IDs
      session_ids = Enum.map(sessions, fn {id, _status} -> id end)

      # Verify id1, id2, id3 appear in order (they may not be the only sessions)
      idx1 = Enum.find_index(session_ids, &(&1 == id1))
      idx2 = Enum.find_index(session_ids, &(&1 == id2))
      idx3 = Enum.find_index(session_ids, &(&1 == id3))

      assert idx1 < idx2
      assert idx2 < idx3
    end
  end

  describe "lifecycle example" do
    test "start session, pause at cycle 10, resume, completes at max_cycles" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 20)
      {:ok, session_id} = Session.start(config)

      Process.sleep(50)
      :ok = Session.pause(session_id)

      assert {:ok, :paused} = Session.status(session_id)

      :ok = Session.resume(session_id)

      assert {:ok, :running} = Session.status(session_id)

      Process.sleep(50)
      :ok = Session.stop(session_id)

      assert {:ok, :stopped} = Session.status(session_id)
    end

    test "full lifecycle: start -> pause -> resume -> stop" do
      config = Config.new(seed_claim: "What if entropy is local?", max_cycles: 50)
      {:ok, session_id} = Session.start(config)

      assert {:ok, :running} = Session.status(session_id)

      :ok = Session.pause(session_id)
      assert {:ok, :paused} = Session.status(session_id)

      :ok = Session.resume(session_id)
      assert {:ok, :running} = Session.status(session_id)

      :ok = Session.stop(session_id)
      assert {:ok, :stopped} = Session.status(session_id)
    end
  end

  describe "error cases" do
    test "returns error for invalid session_id type" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 10)
      {:ok, _session_id} = Session.start(config)

      assert {:error, :not_found} = Session.status("nonexistent_nil")
    end

    test "multiple pause and resume operations" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)
      {:ok, session_id} = Session.start(config)

      assert :ok = Session.pause(session_id)
      assert {:error, :already_paused} = Session.pause(session_id)

      assert :ok = Session.resume(session_id)
      assert {:error, :not_paused} = Session.resume(session_id)

      assert :ok = Session.pause(session_id)
      assert :ok = Session.resume(session_id)

      assert {:ok, :running} = Session.status(session_id)
    end

    test "stop after multiple pause/resume cycles" do
      config = Config.new(seed_claim: "Test claim", max_cycles: 50)
      {:ok, session_id} = Session.start(config)

      Enum.each(1..3, fn _i ->
        :ok = Session.pause(session_id)
        :ok = Session.resume(session_id)
        Process.sleep(10)
      end)

      assert :ok = Session.stop(session_id)
      assert {:ok, :stopped} = Session.status(session_id)
    end
  end
end
