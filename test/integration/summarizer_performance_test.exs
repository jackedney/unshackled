defmodule Unshackled.Integration.SummarizerPerformanceTest do
  use ExUnit.Case, async: false

  alias Unshackled.Evolution.Config, as: EvolutionConfig

  @moduletag :capture_log
  @moduletag :integration

  describe "US-010: Verify cost and performance" do
    test "summarizer configuration uses haiku model for minimal cost" do
      model = EvolutionConfig.summarizer_model()

      assert model == "anthropic/claude-haiku-4.5",
             "Expected summarizer model to be anthropic/claude-haiku-4.5 for minimal cost, got #{model}"
    end

    test "summarizer debounce is disabled for always-on mode" do
      debounce = EvolutionConfig.summarizer_debounce_cycles()

      assert debounce == 0,
             "Expected summarizer debounce to be 0 (always-on mode), got #{debounce}"
    end

    test "haiku model name indicates cost-optimized choice" do
      model = EvolutionConfig.summarizer_model()

      assert String.contains?(model, "haiku"),
             "Model should contain 'haiku' indicating cost-optimized choice, got #{model}"
    end

    test "cycle runner has trigger_summarizer function for per-cycle execution" do
      runner_source = File.read!("lib/unshackled/cycle/runner.ex")

      assert String.contains?(runner_source, "defp trigger_summarizer(state)"),
             "Runner should have trigger_summarizer function for per-cycle summarizer execution"

      assert String.contains?(
               runner_source,
               "Task.start(fn -> trigger_summarizer_async(blackboard_id) end)"
             ),
             "Summarizer should be triggered asynchronously via Task.start"
    end

    test "summarizer is called asynchronously to prevent blocking" do
      runner_source = File.read!("lib/unshackled/cycle/runner.ex")

      assert String.contains?(
               runner_source,
               "Task.start(fn -> trigger_summarizer_async(blackboard_id) end)"
             ),
             "Summarizer should be triggered asynchronously via Task.start to prevent blocking"
    end

    test "reset_phase calls trigger_summarizer after snapshot creation" do
      runner_source = File.read!("lib/unshackled/cycle/runner.ex")

      lines = String.split(runner_source, "\n")

      reset_phase_line =
        Enum.find_index(lines, fn line -> String.contains?(line, "defp reset_phase(state)") end)

      create_snapshot_line =
        Enum.find_index(lines, fn line -> String.contains?(line, "Server.create_snapshot") end)

      trigger_summarizer_line =
        Enum.find_index(lines, fn line -> String.contains?(line, "trigger_summarizer(state)") end)

      assert reset_phase_line != nil, "reset_phase function should exist"
      assert create_snapshot_line != nil, "snapshot creation should exist in reset_phase"
      assert trigger_summarizer_line != nil, "trigger_summarizer should be called in reset_phase"

      assert trigger_summarizer_line > create_snapshot_line,
             "trigger_summarizer should be called after snapshot creation"
    end

    test "summarizer runs per cycle without debounce check" do
      runner_source = File.read!("lib/unshackled/cycle/runner.ex")

      refute String.contains?(runner_source, "trigger_summarizer_if_debounce_allows"),
             "Deprecated trigger_summarizer_if_debounce_allows function should not be used"

      assert String.contains?(runner_source, "trigger_summarizer(state)"),
             "New trigger_summarizer function should be used for unconditional execution"
    end
  end
end
