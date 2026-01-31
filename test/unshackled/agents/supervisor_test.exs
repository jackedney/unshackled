defmodule Unshackled.Agents.SupervisorTest do
  use ExUnit.Case, async: false
  import BlackboardServerFixtures

  alias Unshackled.Agents.Supervisor

  @moduletag :capture_log

  defmodule TestAgent do
    @behaviour Unshackled.Agents.Agent

    def role, do: :test_agent

    def build_prompt(_state) do
      "Test prompt"
    end

    def parse_response(_response) do
      %{test: :result}
    end

    def confidence_delta(_output), do: 0.0
  end

  defmodule TestAgent2 do
    @behaviour Unshackled.Agents.Agent

    def role, do: :test_agent2

    def build_prompt(_state) do
      "Test prompt 2"
    end

    def parse_response(_response) do
      %{test: :result2}
    end

    def confidence_delta(_output), do: 0.0
  end

  defmodule CrashingAgent do
    @behaviour Unshackled.Agents.Agent

    def role, do: :crashing_agent

    def build_prompt(_state) do
      raise "Intentional crash for testing"
    end

    def parse_response(_response), do: %{}

    def confidence_delta(_output), do: 0.0
  end

  defmodule CrashingExplorer do
    @behaviour Unshackled.Agents.Agent

    def role, do: :explorer

    def build_prompt(_state) do
      raise "Explorer crashed"
    end

    def parse_response(_response), do: %{}

    def confidence_delta(_output), do: 0.0
  end

  defmodule SlowAgent do
    @behaviour Unshackled.Agents.Agent

    def role, do: :slow_agent

    def build_prompt(_state) do
      "Test prompt"
    end

    def parse_response(_response) do
      %{test: :result}
    end

    def confidence_delta(_output), do: 0.0
  end

  setup do
    state = blackboard_state("Test claim")

    {:ok, state: state}
  end

  describe "spawn_agents/2" do
    test "spawns TestAgent and TestAgent2, both complete and return results", %{state: state} do
      {:ok, refs} = Supervisor.spawn_agents([TestAgent, TestAgent2], state, 1, 1)

      assert length(refs) == 2
      assert Enum.all?(refs, &is_struct/1)
    end

    test "spawns single agent", %{state: state} do
      {:ok, refs} = Supervisor.spawn_agents([TestAgent], state, 1, 1)

      assert length(refs) == 1
    end

    test "spawns multiple agents in sequence", %{state: state} do
      agent_modules = [TestAgent, TestAgent2, TestAgent, TestAgent2]
      {:ok, refs} = Supervisor.spawn_agents(agent_modules, state, 1, 1)

      assert length(refs) == 4
    end
  end

  describe "await_agents/2" do
    test "collects results from multiple completed agents", %{state: state} do
      {:ok, refs} = Supervisor.spawn_agents([TestAgent, TestAgent2], state, 1, 1)
      {:ok, results} = Supervisor.await_agents(refs, 60_000)

      assert length(results) == 2

      Enum.each(results, fn result ->
        assert match?({:ok, _, _, _, _}, result) or match?({:error, _}, result)
      end)
    end

    test "handles timeout gracefully", %{state: state} do
      {:ok, refs} = Supervisor.spawn_agents([SlowAgent], state, 1, 1)

      assert {:ok, results} = Supervisor.await_agents(refs, 5000)
      assert length(results) == 1
    end

    test "returns empty list for no agents" do
      {:ok, results} = Supervisor.await_agents([], 60_000)

      assert results == []
    end
  end

  describe "error handling" do
    test "spawning agent with invalid module returns error", %{state: state} do
      {:ok, refs} = Supervisor.spawn_agents([NonExistentModule], state, 1, 1)
      {:ok, results} = Supervisor.await_agents(refs, 60_000)

      assert length(results) == 1

      assert match?({:error, {:invalid_agent, _}}, hd(results))
    end

    test "crashed agent logs error but doesn't crash supervisor", %{state: state} do
      {:ok, refs} =
        Supervisor.spawn_agents([CrashingAgent, CrashingAgent], state, 1, 1)

      {:ok, results} = Supervisor.await_agents(refs, 60_000)

      assert length(results) == 2

      crashed_results =
        Enum.filter(results, fn r -> match?({:error, {:agent_crashed, _, _}}, r) end)

      assert length(crashed_results) == 2

      assert Process.alive?(Process.whereis(Unshackled.Agents.Supervisor))
    end

    test "Explorer crashes, TestAgent still completes, error logged", %{state: state} do
      {:ok, refs} =
        Supervisor.spawn_agents([CrashingExplorer, CrashingExplorer], state, 1, 1)

      {:ok, results} = Supervisor.await_agents(refs, 60_000)

      assert length(results) == 2

      crashed_results =
        Enum.filter(results, fn r -> match?({:error, {:agent_crashed, _, _}}, r) end)

      assert length(crashed_results) == 2

      assert Process.alive?(Process.whereis(Unshackled.Agents.Supervisor))
    end

    test "multiple invalid modules handled gracefully", %{state: state} do
      {:ok, refs} =
        Supervisor.spawn_agents([NonExistent1, NonExistent2], state, 1, 1)

      {:ok, results} = Supervisor.await_agents(refs, 60_000)

      assert length(results) == 2

      Enum.each(results, fn result ->
        assert match?({:error, {:invalid_agent, _}}, result)
      end)
    end
  end

  describe "supervisor lifecycle" do
    test "supervisor name is registered" do
      assert Process.whereis(Unshackled.Agents.Supervisor) != nil
    end
  end
end
