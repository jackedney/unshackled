defmodule Unshackled.Agents.PromptBuilderTest do
  use ExUnit.Case, async: true

  alias Unshackled.Agents.PromptBuilder
  alias Unshackled.Blackboard.Server

  describe "extract_context/1" do
    test "extracts all common fields from Server struct" do
      server = %Server{
        current_claim: "Test claim",
        support_strength: 0.75,
        cycle_count: 10,
        blackboard_id: 123,
        blackboard_name: :test_bb,
        active_objection: "Some objection",
        analogy_of_record: "Test analogy",
        frontier_pool: %{idea: "test"},
        cemetery: [%{claim: "dead"}],
        graduated_claims: [%{claim: "graduated"}],
        embedding: <<1, 2, 3>>,
        translator_frameworks_used: ["framework1"],
        cost_limit_usd: 10.0
      }

      result = PromptBuilder.extract_context(server)

      assert result.current_claim == "Test claim"
      assert result.support_strength == 0.75
      assert result.cycle_count == 10
      assert result.blackboard_id == 123
      assert result.blackboard_name == :test_bb
      assert result.active_objection == "Some objection"
      assert result.analogy_of_record == "Test analogy"
      assert result.frontier_pool == %{idea: "test"}
      assert result.cemetery == [%{claim: "dead"}]
      assert result.graduated_claims == [%{claim: "graduated"}]
      assert result.embedding == <<1, 2, 3>>
      assert result.translator_frameworks_used == ["framework1"]
      assert result.cost_limit_usd == 10.0
    end

    test "returns empty map for nil Server" do
      result = PromptBuilder.extract_context(nil)
      assert result == %{}
    end

    test "raises ArgumentError for non-Server non-nil input" do
      assert_raise ArgumentError, ~r/Expected Server struct or nil/, fn ->
        PromptBuilder.extract_context("not a server")
      end
    end
  end

  describe "has_min_cycles?/2" do
    test "returns true when cycle_count meets minimum requirement" do
      server = %Server{cycle_count: 5}
      assert PromptBuilder.has_min_cycles?(server, 5) == true
      assert PromptBuilder.has_min_cycles?(server, 3) == true
      assert PromptBuilder.has_min_cycles?(server, 4) == true
    end

    test "returns false when cycle_count below minimum requirement" do
      server = %Server{cycle_count: 3}
      assert PromptBuilder.has_min_cycles?(server, 5) == false
      assert PromptBuilder.has_min_cycles?(server, 4) == false
    end

    test "returns false when cycle_count is nil" do
      server = %Server{cycle_count: nil}
      assert PromptBuilder.has_min_cycles?(server, 5) == false
    end

    test "raises ArgumentError for non-Server input" do
      assert_raise ArgumentError, ~r/Expected Server struct with cycle_count/, fn ->
        PromptBuilder.has_min_cycles?("not a server", 5)
      end
    end
  end

  describe "json_instructions/1" do
    test "generates JSON format from map of fields" do
      fields = %{
        new_claim: "Your definitive extension of the claim",
        inference_type: "deductive|inductive|abductive",
        reasoning: "Brief explanation"
      }

      result = PromptBuilder.json_instructions(fields)

      assert result =~ "Required response format (JSON)"
      assert result =~ ~s("new_claim": "Your definitive extension of the claim")
      assert result =~ ~s("inference_type": "deductive|inductive|abductive")
      assert result =~ ~s("reasoning": "Brief explanation")
    end

    test "generates JSON format from keyword list" do
      fields = [
        objection: "Your specific objection",
        target_premise: "The premise you object to"
      ]

      result = PromptBuilder.json_instructions(fields)

      assert result =~ "Required response format (JSON)"
      assert result =~ ~s("objection": "Your specific objection")
      assert result =~ ~s("target_premise": "The premise you object to")
    end

    test "generates correct JSON braces and structure" do
      fields = %{test_field: "test value"}

      result = PromptBuilder.json_instructions(fields)

      assert String.starts_with?(result, "Required response format (JSON)")
      assert result =~ "{\n"
      assert result =~ "\n}"
    end
  end

  describe "error_response/2" do
    test "builds error map with specified fields set to nil" do
      result = PromptBuilder.error_response([:new_claim, :reasoning], "Missing fields")

      assert result.new_claim == nil
      assert result.reasoning == nil
      assert result.valid == false
      assert result.error == "Missing fields"
      assert map_size(result) == 4
    end

    test "builds error map with single field" do
      result = PromptBuilder.error_response([:test_field], "Test error")

      assert result.test_field == nil
      assert result.valid == false
      assert result.error == "Test error"
      assert map_size(result) == 3
    end

    test "builds error map with multiple fields" do
      result =
        PromptBuilder.error_response(
          [:objection, :target_premise, :clarifying_question],
          "Invalid JSON"
        )

      assert result.objection == nil
      assert result.target_premise == nil
      assert result.clarifying_question == nil
      assert result.valid == false
      assert result.error == "Invalid JSON"
      assert map_size(result) == 5
    end

    test "raises ArgumentError when fields is not a list" do
      assert_raise ArgumentError, ~r/Expected field list \(atoms\)/, fn ->
        PromptBuilder.error_response("not a list", "error")
      end
    end

    test "raises ArgumentError when message is not a string" do
      assert_raise ArgumentError,
                   ~r/Expected field list \(atoms\) and error message \(string\)/,
                   fn ->
                     PromptBuilder.error_response([:field], 123)
                   end
    end
  end
end
