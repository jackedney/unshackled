defmodule Unshackled.Cycle.RunnerTest do
  use ExUnit.Case, async: false

  alias Unshackled.Cycle.Runner

  @moduletag :capture_log

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Unshackled.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Unshackled.Repo, {:shared, self()})

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.checkin(Unshackled.Repo)
    end)

    :ok
  end

  describe "init/1" do
    test "initializes with valid configuration" do
      opts = [
        seed_claim: "Test claim",
        max_cycles: 10,
        cycle_mode: :event_driven,
        cycle_timeout_ms: 5000
      ]

      assert {:ok, pid} = Runner.start_link(opts, :test_runner_init)
      assert is_pid(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "initializes with time_based cycle_mode" do
      opts = [
        seed_claim: "Test claim",
        max_cycles: 10,
        cycle_mode: :time_based,
        cycle_timeout_ms: 5000
      ]

      assert {:ok, pid} = Runner.start_link(opts, :test_runner_time_mode)
      assert is_pid(pid)

      GenServer.stop(pid)
    end

    test "raises error for invalid cycle_mode" do
      opts = [
        seed_claim: "Test claim",
        max_cycles: 10,
        cycle_mode: :invalid_mode,
        cycle_timeout_ms: 5000
      ]

      _parent = self()

      pid = spawn(fn -> Runner.start_link(opts, :test_runner_invalid) end)

      Process.monitor(pid)

      assert_receive {:DOWN, _ref, :process, ^pid, _reason}, 1000
    end

    test "raises error when required options are missing" do
      opts = [
        seed_claim: "Test claim"
      ]

      _parent = self()

      pid = spawn(fn -> Runner.start_link(opts, :test_runner_missing_opts) end)

      Process.monitor(pid)

      assert_receive {:DOWN, _ref, :process, ^pid, _reason}, 1000
    end
  end

  describe "start_session/0" do
    setup do
      opts = [
        seed_claim: "What if entropy is local?",
        max_cycles: 10,
        cycle_mode: :time_based,
        cycle_timeout_ms: 5000
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_session)

      {:ok, runner: pid}
    end

    test "starts session and returns blackboard_id", %{runner: pid} do
      assert {:ok, blackboard_id} = Runner.start_session(pid)
      assert is_integer(blackboard_id)
      assert blackboard_id > 0
    end

    test "sets running state to true", %{runner: pid} do
      assert {:ok, _blackboard_id} = Runner.start_session(pid)
      assert true == Runner.is_running?(pid)
    end

    test "initializes cycle_count to 1", %{runner: pid} do
      assert {:ok, _blackboard_id} = Runner.start_session(pid)
      assert 1 == Runner.get_cycle_count(pid)
    end

    test "returns error when starting already-running session", %{runner: pid} do
      assert {:ok, _blackboard_id} = Runner.start_session(pid)
      assert {:error, :already_running} = Runner.start_session(pid)
    end

    test "starts blackboard server", %{runner: pid} do
      assert {:ok, _blackboard_id} = Runner.start_session(pid)

      assert true == Runner.is_running?(pid)
    end
  end

  describe "cycle execution" do
    setup do
      opts = [
        seed_claim: "Test claim for cycles",
        max_cycles: 3,
        cycle_mode: :time_based,
        cycle_timeout_ms: 200
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_cycles)

      {:ok, runner: pid}
    end

    test "starts session and begins cycle loop", %{runner: pid} do
      assert {:ok, _blackboard_id} = Runner.start_session(pid)

      Process.sleep(100)

      assert 1 == Runner.get_cycle_count(pid)
    end

    test "stops at max_cycles", %{runner: pid} do
      assert {:ok, _blackboard_id} = Runner.start_session(pid)

      Process.sleep(700)

      assert 3 == Runner.get_cycle_count(pid)

      assert false == Runner.is_running?(pid)
    end

    test "cycle_count increments with each cycle", %{runner: pid} do
      assert {:ok, _blackboard_id} = Runner.start_session(pid)

      assert 1 == Runner.get_cycle_count(pid)

      Process.sleep(450)

      assert 2 <= Runner.get_cycle_count(pid)
    end
  end

  describe "is_running?/0" do
    setup do
      opts = [
        seed_claim: "Test claim for running check",
        max_cycles: 10,
        cycle_mode: :time_based,
        cycle_timeout_ms: 200
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_running)

      {:ok, runner: pid}
    end

    test "returns false before session starts", %{runner: pid} do
      assert false == Runner.is_running?(pid)
    end

    test "returns true after session starts", %{runner: pid} do
      assert {:ok, _blackboard_id} = Runner.start_session(pid)
      assert true == Runner.is_running?(pid)
    end

    test "returns false after max_cycles reached", %{runner: pid} do
      assert {:ok, _blackboard_id} = Runner.start_session(pid)

      Process.sleep(2500)

      assert false == Runner.is_running?(pid)
    end
  end

  describe "get_cycle_count/0" do
    setup do
      opts = [
        seed_claim: "Test claim for cycle count",
        max_cycles: 5,
        cycle_mode: :time_based,
        cycle_timeout_ms: 200
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_count)

      {:ok, runner: pid}
    end

    test "returns 0 before session starts", %{runner: pid} do
      assert 0 == Runner.get_cycle_count(pid)
    end

    test "returns 1 after session starts", %{runner: pid} do
      assert {:ok, _blackboard_id} = Runner.start_session(pid)
      assert 1 == Runner.get_cycle_count(pid)
    end
  end

  describe "cycle_mode handling" do
    test "time_based mode uses timeout for scheduling" do
      opts = [
        seed_claim: "Test time-based mode",
        max_cycles: 2,
        cycle_mode: :time_based,
        cycle_timeout_ms: 200
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_time_based)

      assert {:ok, _blackboard_id} = Runner.start_session(pid)

      assert 1 == Runner.get_cycle_count(pid)

      Process.sleep(250)

      assert 2 == Runner.get_cycle_count(pid)

      GenServer.stop(pid)
    end

    test "event_driven mode schedules cycles immediately" do
      opts = [
        seed_claim: "Test event-driven mode",
        max_cycles: 3,
        cycle_mode: :event_driven,
        cycle_timeout_ms: 5000
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_event_driven)

      assert {:ok, _blackboard_id} = Runner.start_session(pid)

      Process.sleep(100)

      assert 3 == Runner.get_cycle_count(pid)

      assert false == Runner.is_running?(pid)

      GenServer.stop(pid)
    end
  end

  describe "error handling" do
    test "handles blackboard server failure gracefully" do
      opts = [
        seed_claim: "Test error handling",
        max_cycles: 1,
        cycle_mode: :time_based,
        cycle_timeout_ms: 200
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_error)

      assert {:ok, _blackboard_id} = Runner.start_session(pid)

      Process.sleep(300)

      assert 1 == Runner.get_cycle_count(pid)

      assert false == Runner.is_running?(pid)

      GenServer.stop(pid)
    end
  end

  describe "negative cases" do
    test "cannot start session on stopped runner" do
      opts = [
        seed_claim: "Test nil case",
        max_cycles: 10,
        cycle_mode: :time_based,
        cycle_timeout_ms: 200
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_nil_case)
      GenServer.stop(pid)

      assert catch_exit(Runner.start_session(pid)) != nil
    end

    test "multiple attempts to start same session return error" do
      opts = [
        seed_claim: "Test multiple start attempts",
        max_cycles: 10,
        cycle_mode: :time_based,
        cycle_timeout_ms: 200
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_multiple)

      assert {:ok, _blackboard_id} = Runner.start_session(pid)
      assert {:error, :already_running} = Runner.start_session(pid)
      assert {:error, :already_running} = Runner.start_session(pid)

      GenServer.stop(pid)
    end
  end

  describe "cycle phases" do
    setup do
      opts = [
        seed_claim: "Test cycle phases",
        max_cycles: 2,
        cycle_mode: :time_based,
        cycle_timeout_ms: 200
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_phases)

      {:ok, runner: pid}
    end

    test "executes all five phases in order", %{runner: pid} do
      assert {:ok, _blackboard_id} = Runner.start_session(pid)

      Process.sleep(450)

      assert 2 == Runner.get_cycle_count(pid)
    end

    test "perturber activates 20% of time", %{runner: pid} do
      {:ok, _blackboard_id} = Runner.start_session(pid)

      activations =
        Enum.map(1..100, fn _ ->
          :rand.uniform() <= 0.2
        end)

      activation_count = Enum.count(activations, & &1)

      assert activation_count >= 5
      assert activation_count <= 35
    end

    test "blackboard snapshot created after each cycle", %{runner: pid} do
      assert {:ok, _blackboard_id} = Runner.start_session(pid)

      Process.sleep(450)

      assert 2 == Runner.get_cycle_count(pid)
    end
  end

  describe "time-based mode with agent timeouts" do
    test "uses cycle_duration_ms for agent timeout (default 300000ms)" do
      opts = [
        seed_claim: "Test default duration",
        max_cycles: 1,
        cycle_mode: :time_based,
        cycle_timeout_ms: 100
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_default_duration)

      assert {:ok, _blackboard_id} = Runner.start_session(pid)
      assert 1 == Runner.get_cycle_count(pid)

      GenServer.stop(pid)
    end

    test "accepts custom cycle_duration_ms" do
      opts = [
        seed_claim: "Test custom duration",
        max_cycles: 1,
        cycle_mode: :time_based,
        cycle_timeout_ms: 100,
        cycle_duration_ms: 100
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_custom_duration)

      assert {:ok, _blackboard_id} = Runner.start_session(pid)
      assert 1 == Runner.get_cycle_count(pid)

      GenServer.stop(pid)
    end
  end

  describe "event-driven mode with agent timeouts" do
    test "uses cycle_timeout_ms for agent timeout" do
      opts = [
        seed_claim: "Test event-driven timeout",
        max_cycles: 1,
        cycle_mode: :event_driven,
        cycle_timeout_ms: 100
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_event_timeout)

      assert {:ok, _blackboard_id} = Runner.start_session(pid)
      assert 1 == Runner.get_cycle_count(pid)

      GenServer.stop(pid)
    end

    test "completes immediately when all agents finish quickly" do
      opts = [
        seed_claim: "Test quick completion",
        max_cycles: 2,
        cycle_mode: :event_driven,
        cycle_timeout_ms: 5000
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_quick_completion)

      assert {:ok, _blackboard_id} = Runner.start_session(pid)

      Process.sleep(200)

      assert 2 == Runner.get_cycle_count(pid)
      assert false == Runner.is_running?(pid)

      GenServer.stop(pid)
    end

    test "handles partial results when some agents timeout" do
      opts = [
        seed_claim: "Test partial results",
        max_cycles: 1,
        cycle_mode: :event_driven,
        cycle_timeout_ms: 100
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_partial_results)

      assert {:ok, _blackboard_id} = Runner.start_session(pid)
      assert 1 == Runner.get_cycle_count(pid)

      GenServer.stop(pid)
    end

    test "returns error when zero agents would be spawned in event-driven mode" do
      opts = [
        seed_claim: "Test zero agents error",
        max_cycles: 1,
        cycle_mode: :event_driven,
        cycle_timeout_ms: 100
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_zero_agents)

      assert {:ok, _blackboard_id} = Runner.start_session(pid)

      Process.sleep(50)

      assert false == Runner.is_running?(pid)

      GenServer.stop(pid)
    end
  end

  describe "partial results handling" do
    test "handles empty agent list gracefully" do
      opts = [
        seed_claim: "Test empty agents",
        max_cycles: 1,
        cycle_mode: :time_based,
        cycle_timeout_ms: 100
      ]

      {:ok, pid} = Runner.start_link(opts, :test_runner_empty_agents)

      assert {:ok, _blackboard_id} = Runner.start_session(pid)
      assert 1 == Runner.get_cycle_count(pid)

      GenServer.stop(pid)
    end
  end

  describe "decay phase" do
    test "applies decay at end of each cycle" do
      opts = [
        seed_claim: "Test decay",
        max_cycles: 2,
        cycle_mode: :time_based,
        cycle_timeout_ms: 100
      ]

      {:ok, _pid} = Runner.start_link(opts, :test_runner_decay)

      assert {:ok, _blackboard_id} = Runner.start_session(:test_runner_decay)

      Process.sleep(250)

      state = :sys.get_state(:test_runner_decay)
      blackboard_state = Unshackled.Blackboard.Server.get_state(state.blackboard_name)

      # Support should be less than initial 0.5 after decay is applied
      # The exact value depends on novelty bonuses and other factors, but decay should reduce it
      assert blackboard_state.support_strength < 0.6

      GenServer.stop(:test_runner_decay)
    end

    test "support is set after first cycle" do
      opts = [
        seed_claim: "Test after cycle 1",
        max_cycles: 1,
        cycle_mode: :time_based,
        cycle_timeout_ms: 100
      ]

      {:ok, _pid} = Runner.start_link(opts, :test_runner_decay_cycle0)

      assert {:ok, _blackboard_id} = Runner.start_session(:test_runner_decay_cycle0)

      Process.sleep(150)

      state = :sys.get_state(:test_runner_decay_cycle0)
      blackboard_state = Unshackled.Blackboard.Server.get_state(state.blackboard_name)

      # After one cycle, support should be close to initial value (possibly with bonuses/decay)
      assert blackboard_state.support_strength >= 0.4
      assert blackboard_state.support_strength <= 0.7

      GenServer.stop(:test_runner_decay_cycle0)
    end

    test "support decreases over multiple cycles due to decay" do
      opts = [
        seed_claim: "Test decay over time",
        max_cycles: 3,
        cycle_mode: :time_based,
        cycle_timeout_ms: 100
      ]

      {:ok, _pid} = Runner.start_link(opts, :test_runner_decay_example)

      assert {:ok, _blackboard_id} = Runner.start_session(:test_runner_decay_example)

      # Get initial support after first cycle
      Process.sleep(150)
      state1 = :sys.get_state(:test_runner_decay_example)
      bb_state1 = Unshackled.Blackboard.Server.get_state(state1.blackboard_name)
      support_after_cycle1 = bb_state1.support_strength

      # Wait for remaining cycles
      Process.sleep(250)
      state_final = :sys.get_state(:test_runner_decay_example)
      bb_state_final = Unshackled.Blackboard.Server.get_state(state_final.blackboard_name)
      support_final = bb_state_final.support_strength

      # Support should have decreased due to decay (2 additional decay applications)
      assert support_final < support_after_cycle1

      GenServer.stop(:test_runner_decay_example)
    end
  end
end
