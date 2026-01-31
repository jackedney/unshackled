defmodule Unshackled.Cycle.ArbiterTest do
  use ExUnit.Case, async: true
  alias Unshackled.Cycle.Arbiter
  alias Unshackled.Blackboard.Server

  describe "evaluate/2" do
    test "accepts valid Explorer and Critic when Critic targets unrelated premise" do
      agent_results = [
        {:ok, :explorer, "gpt-4",
         %{valid: true, new_claim: "Therefore heat flows from hot to cold"}, 0.10},
        {:ok, :critic, "claude-3",
         %{valid: true, objection: "X is wrong", target_premise: "unrelated premise"}, -0.15}
      ]

      state = %Server{current_claim: "Entropy increases"}

      assert {:ok, accepted} = Arbiter.evaluate(agent_results, state)
      assert length(accepted) == 2
      roles = Enum.map(accepted, fn c -> c.role end)
      assert :explorer in roles
      assert :critic in roles
    end

    test "accepts Explorer when Critic targeting it is invalid" do
      agent_results = [
        {:ok, :explorer, "gpt-4",
         %{valid: true, new_claim: "Therefore heat flows from hot to cold"}, 0.10},
        {:ok, :critic, "claude-3",
         %{
           valid: false,
           error: "target_premise is a conclusion indicator, not an actual premise",
           objection: "This is wrong",
           target_premise: "Therefore heat flows from hot to cold"
         }, -0.15}
      ]

      state = %Server{current_claim: "Entropy increases"}

      assert {:ok, accepted} = Arbiter.evaluate(agent_results, state)
      assert length(accepted) == 1
      assert hd(accepted).role == :explorer
    end

    test "accepts valid Critic objection" do
      agent_results = [
        {:ok, :critic, "claude-3",
         %{valid: true, objection: "Isolation is ambiguous", target_premise: "isolated regions"},
         -0.15}
      ]

      state = %Server{current_claim: "Entropy increases in isolated regions"}

      assert {:ok, accepted} = Arbiter.evaluate(agent_results, state)
      assert length(accepted) == 1
      assert hd(accepted).role == :critic
      assert hd(accepted).output.valid == true
    end

    test "rejects Critic when targeting conclusion" do
      agent_results = [
        {:ok, :critic, "claude-3",
         %{
           valid: false,
           error: "Objection targets conclusion rather than premise",
           objection: "This conclusion is wrong",
           target_premise: "conclusion"
         }, 0.0}
      ]

      state = %Server{current_claim: "Therefore heat flows"}

      assert {:ok, accepted} = Arbiter.evaluate(agent_results, state)
      assert length(accepted) == 0
    end

    test "accepts Connector with specific enough analogy" do
      agent_results = [
        {:ok, :connector, "claude-3",
         %{
           valid: true,
           analogy:
             "This is like Shannon's entropy in information theory because both measure disorder",
           source_domain: "information theory",
           mapping_explanation: "Both quantify microstates in different domains"
         }, 0.05}
      ]

      state = %Server{current_claim: "Thermodynamic entropy increases"}

      assert {:ok, accepted} = Arbiter.evaluate(agent_results, state)
      assert length(accepted) == 1
      assert hd(accepted).role == :connector
      assert hd(accepted).output.valid == true
    end

    test "rejects Connector with vague analogy" do
      agent_results = [
        {:ok, :connector, "claude-3",
         %{
           valid: false,
           error: "Analogy is too vague - must be specific and testable",
           analogy: "This is like many things in nature",
           source_domain: "nature",
           mapping_explanation: "Many natural systems exhibit patterns"
         }, 0.0}
      ]

      state = %Server{current_claim: "Entropy increases"}

      assert {:ok, accepted} = Arbiter.evaluate(agent_results, state)
      assert length(accepted) == 0
    end

    test "accepts valid other agents" do
      agent_results = [
        {:ok, :steelman, "claude-3",
         %{
           valid: true,
           counter_argument: "Universal entropy holds",
           key_assumptions: ["system is closed"]
         }, -0.05},
        {:ok, :quantifier, "gpt-4",
         %{
           valid: true,
           quantified_claim: "Entropy increases at scales below 10^-9 meters",
           bounds: "10^-9"
         }, 0.05}
      ]

      state = %Server{current_claim: "Entropy increases"}

      assert {:ok, accepted} = Arbiter.evaluate(agent_results, state)
      assert length(accepted) == 2
      roles = Enum.map(accepted, fn c -> c.role end)
      assert :steelman in roles
      assert :quantifier in roles
    end

    test "rejects invalid other agents" do
      agent_results = [
        {:ok, :steelman, "claude-3",
         %{valid: false, error: "Invalid format", counter_argument: nil}, 0.0}
      ]

      state = %Server{current_claim: "Entropy increases"}

      assert {:ok, accepted} = Arbiter.evaluate(agent_results, state)
      assert length(accepted) == 0
    end

    test "accepts Explorer and Critic when both valid and not targeting each other" do
      agent_results = [
        {:ok, :explorer, "gpt-4",
         %{valid: true, new_claim: "Therefore heat flows from hot to cold"}, 0.10},
        {:ok, :critic, "claude-3",
         %{valid: true, objection: "Premise Y is weak", target_premise: "unrelated premise"},
         -0.15}
      ]

      state = %Server{current_claim: "Entropy increases"}

      assert {:ok, accepted} = Arbiter.evaluate(agent_results, state)
      assert length(accepted) == 2
      roles = Enum.map(accepted, fn x -> x.role end)
      assert :explorer in roles
      assert :critic in roles
    end

    test "filters out error results" do
      agent_results = [
        {:ok, :explorer, "gpt-4", %{valid: true, new_claim: "X"}, 0.10},
        {:error, {:timeout, 60000}},
        {:error, {:agent_crashed, :explorer}}
      ]

      state = %Server{current_claim: "Claim"}

      assert {:ok, accepted} = Arbiter.evaluate(agent_results, state)
      assert length(accepted) == 1
      assert hd(accepted).role == :explorer
    end

    test "filters out results with invalid output format" do
      agent_results = [
        {:ok, :explorer, "gpt-4", %{valid: false, error: "Hedging detected"}, 0.0},
        {:ok, :critic, "claude-3", %{valid: true, objection: "X", target_premise: "Y"}, -0.15}
      ]

      state = %Server{current_claim: "Claim"}

      assert {:ok, accepted} = Arbiter.evaluate(agent_results, state)
      assert length(accepted) == 1
      assert hd(accepted).role == :critic
    end

    test "handles empty agent results" do
      agent_results = []
      state = %Server{current_claim: "Claim"}

      assert {:ok, accepted} = Arbiter.evaluate(agent_results, state)
      assert length(accepted) == 0
    end

    test "handles multiple Explorers and Critics correctly" do
      agent_results = [
        {:ok, :explorer, "gpt-4", %{valid: true, new_claim: "Claim A extends X"}, 0.10},
        {:ok, :explorer, "gpt-4", %{valid: true, new_claim: "Claim B extends X"}, 0.10},
        {:ok, :critic, "claude-3",
         %{valid: true, objection: "Y is weak", target_premise: "Claim A extends X"}, -0.15},
        {:ok, :critic, "claude-3",
         %{valid: true, objection: "Z is weak", target_premise: "unrelated premise"}, -0.15}
      ]

      state = %Server{current_claim: "X"}

      assert {:ok, accepted} = Arbiter.evaluate(agent_results, state)
      assert length(accepted) == 3

      roles = Enum.map(accepted, fn c -> c.role end)
      assert Enum.count(roles, fn r -> r == :explorer end) == 1
      assert Enum.count(roles, fn r -> r == :critic end) == 2
    end

    test "includes model_used and confidence_delta in accepted contributions" do
      agent_results = [
        {:ok, :explorer, "gpt-4", %{valid: true, new_claim: "X"}, 0.10}
      ]

      state = %Server{current_claim: "Claim"}

      assert {:ok, accepted} = Arbiter.evaluate(agent_results, state)
      assert length(accepted) == 1

      contribution = hd(accepted)
      assert contribution.role == :explorer
      assert contribution.model_used == "gpt-4"
      assert contribution.confidence_delta == 0.10
      assert contribution.output.valid == true
    end

    test "accepts Connector with valid output containing all required fields" do
      agent_results = [
        {:ok, :connector, "claude-3",
         %{
           valid: true,
           analogy: "Like market equilibrium",
           source_domain: "economics",
           mapping_explanation: "Both reach balance through opposing forces"
         }, 0.05}
      ]

      state = %Server{current_claim: "Claim"}

      assert {:ok, accepted} = Arbiter.evaluate(agent_results, state)
      assert length(accepted) == 1

      contribution = hd(accepted)
      assert contribution.role == :connector
      assert contribution.output.valid == true
      assert contribution.output.analogy != nil
      assert contribution.output.source_domain != nil
      assert contribution.output.mapping_explanation != nil
    end

    test "Critic targeting 'conclusion' is rejected even with valid: true" do
      agent_results = [
        {:ok, :critic, "claude-3",
         %{
           valid: false,
           error: "target_premise is a conclusion indicator, not an actual premise",
           objection: "This is wrong",
           target_premise: "therefore"
         }, -0.15}
      ]

      state = %Server{current_claim: "Claim"}

      assert {:ok, accepted} = Arbiter.evaluate(agent_results, state)
      assert length(accepted) == 0
    end
  end
end
