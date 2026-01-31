defmodule Unshackled.Cycle.SchedulerTest do
  use ExUnit.Case, async: true
  alias Unshackled.Blackboard.Server
  alias Unshackled.Cycle.Scheduler

  describe "agents_for_cycle/2" do
    test "includes core agents every cycle" do
      state = %Server{cycle_count: 1, support_strength: 0.5, blackboard_id: 1}

      agents = Scheduler.agents_for_cycle(1, state)

      assert Unshackled.Agents.Explorer in agents
      assert Unshackled.Agents.Critic in agents
    end

    test "includes analytical agents every 3 cycles" do
      state = %Server{cycle_count: 3, support_strength: 0.5, blackboard_id: 1}

      agents = Scheduler.agents_for_cycle(3, state)

      assert Unshackled.Agents.Connector in agents
      assert Unshackled.Agents.Steelman in agents
      assert Unshackled.Agents.Operationalizer in agents
      assert Unshackled.Agents.Quantifier in agents
    end

    test "does not include analytical agents on non-multiple of 3" do
      state = %Server{cycle_count: 2, support_strength: 0.5, blackboard_id: 1}

      agents = Scheduler.agents_for_cycle(2, state)

      assert Unshackled.Agents.Connector not in agents
      assert Unshackled.Agents.Steelman not in agents
      assert Unshackled.Agents.Operationalizer not in agents
      assert Unshackled.Agents.Quantifier not in agents
    end

    test "includes structural agents every 5 cycles" do
      state = %Server{cycle_count: 5, support_strength: 0.5, blackboard_id: 1}

      agents = Scheduler.agents_for_cycle(5, state)

      assert Unshackled.Agents.Reducer in agents
      assert Unshackled.Agents.BoundaryHunter in agents
      assert Unshackled.Agents.Translator in agents
    end

    test "does not include structural agents on non-multiple of 5" do
      state = %Server{cycle_count: 4, support_strength: 0.5, blackboard_id: 1}

      agents = Scheduler.agents_for_cycle(4, state)

      assert Unshackled.Agents.Reducer not in agents
      assert Unshackled.Agents.BoundaryHunter not in agents
      assert Unshackled.Agents.Translator not in agents
    end

    test "includes historian every 5 cycles (after cycle 0)" do
      state = %Server{cycle_count: 5, support_strength: 0.5, blackboard_id: 1}

      agents = Scheduler.agents_for_cycle(5, state)

      assert Unshackled.Agents.Historian in agents
    end

    test "raises error for cycle 0 (cycles start at 1)" do
      state = %Server{cycle_count: 0, support_strength: 0.5, blackboard_id: 1}

      assert_raise ArgumentError, "Cycle count must be at least 1, got 0", fn ->
        Scheduler.agents_for_cycle(0, state)
      end
    end

    test "includes grave keeper when support is low" do
      state = %Server{cycle_count: 1, support_strength: 0.3, blackboard_id: 1}

      agents = Scheduler.agents_for_cycle(1, state)

      assert Unshackled.Agents.GraveKeeper in agents
    end

    test "does not include grave keeper when support is high" do
      state = %Server{cycle_count: 1, support_strength: 0.7, blackboard_id: 1}

      agents = Scheduler.agents_for_cycle(1, state)

      assert Unshackled.Agents.GraveKeeper not in agents
    end

    test "does not include cartographer before cycle 5" do
      state = %Server{cycle_count: 3, support_strength: 0.5, blackboard_id: 1}

      agents = Scheduler.agents_for_cycle(3, state)

      assert Unshackled.Agents.Cartographer not in agents
    end

    test "does not include cartographer without blackboard_id" do
      state = %Server{cycle_count: 10, support_strength: 0.5, blackboard_id: nil}

      agents = Scheduler.agents_for_cycle(10, state)

      assert Unshackled.Agents.Cartographer not in agents
    end

    test "includes perturber with 20% probability" do
      state = %Server{cycle_count: 1, support_strength: 0.5}

      agent_lists = for _ <- 1..100, do: Scheduler.agents_for_cycle(1, state)

      perturber_count =
        agent_lists
        |> Enum.count(fn agents -> Unshackled.Agents.Perturber in agents end)

      assert perturber_count > 5 and perturber_count < 35
    end

    test "returns unique agent list" do
      state = %Server{cycle_count: 6, support_strength: 0.5, blackboard_id: 1}

      agents = Scheduler.agents_for_cycle(6, state)

      assert length(agents) == length(Enum.uniq(agents))
    end
  end
end
