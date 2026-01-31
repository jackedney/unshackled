defmodule Unshackled.Agents.ExplorerTest do
  use Unshackled.DataCase, async: true

  alias Unshackled.Agents.Explorer

  describe "parse_response/1" do
    test "valid JSON with all fields returns {:ok, %ExplorerSchema{}}" do
      valid_json = ~s({
        "new_claim": "Heat flows from hot to cold in isolated regions due to local entropy increase",
        "inference_type": "deductive",
        "reasoning": "Local entropy increase implies thermodynamic gradients cause heat flow"
      })

      assert {:ok, schema} = Explorer.parse_response(valid_json)

      assert schema.new_claim ==
               "Heat flows from hot to cold in isolated regions due to local entropy increase"

      assert schema.inference_type == "deductive"

      assert schema.reasoning ==
               "Local entropy increase implies thermodynamic gradients cause heat flow"
    end

    test "valid JSON with inductive inference_type returns {:ok, %ExplorerSchema{}}" do
      valid_json = ~s({
        "new_claim": "Most systems tend toward equilibrium over time",
        "inference_type": "inductive",
        "reasoning": "Observed patterns suggest this generalization"
      })

      assert {:ok, schema} = Explorer.parse_response(valid_json)
      assert schema.inference_type == "inductive"
    end

    test "valid JSON with abductive inference_type returns {:ok, %ExplorerSchema{}}" do
      valid_json = ~s({
        "new_claim": "The data suggests a hidden variable is influencing outcomes",
        "inference_type": "abductive",
        "reasoning": "Best explanation for observed phenomenon"
      })

      assert {:ok, schema} = Explorer.parse_response(valid_json)
      assert schema.inference_type == "abductive"
    end

    test "missing new_claim field returns {:error, changeset} with error on :new_claim" do
      invalid_json = ~s({
        "inference_type": "deductive",
        "reasoning": "Test reasoning"
      })

      assert {:error, changeset} = Explorer.parse_response(invalid_json)
      refute changeset.valid?
      assert [new_claim: {"can't be blank", _}] = changeset.errors
    end

    test "missing inference_type field returns {:error, changeset} with error on :inference_type" do
      invalid_json = ~s({
        "new_claim": "Test claim",
        "reasoning": "Test reasoning"
      })

      assert {:error, changeset} = Explorer.parse_response(invalid_json)
      refute changeset.valid?
      assert [inference_type: {"can't be blank", _}] = changeset.errors
    end

    test "invalid inference_type 'magical' returns {:error, changeset}" do
      invalid_json = ~s({
        "new_claim": "Test claim",
        "inference_type": "magical",
        "reasoning": "Test reasoning"
      })

      assert {:error, changeset} = Explorer.parse_response(invalid_json)
      refute changeset.valid?
      assert [inference_type: {"is invalid", _}] = changeset.errors
    end

    test "invalid inference_type 'random' returns {:error, changeset}" do
      invalid_json = ~s({
        "new_claim": "Test claim",
        "inference_type": "random",
        "reasoning": "Test reasoning"
      })

      assert {:error, changeset} = Explorer.parse_response(invalid_json)
      refute changeset.valid?
      assert [inference_type: {"is invalid", _}] = changeset.errors
    end

    test "invalid JSON format returns {:error, changeset} with JSON error" do
      invalid_json = "This is not valid JSON"

      assert {:error, changeset} = Explorer.parse_response(invalid_json)
      refute changeset.valid?

      assert Enum.any?(changeset.errors, fn
               {:json, {"Invalid JSON format", _}} -> true
               _ -> false
             end)
    end

    test "malformed JSON returns {:error, changeset}" do
      invalid_json = "{malformed json"

      assert {:error, changeset} = Explorer.parse_response(invalid_json)
      refute changeset.valid?

      assert Enum.any?(changeset.errors, fn
               {:json, {"Invalid JSON format", _}} -> true
               _ -> false
             end)
    end

    test "hedging words in claim return {:error, changeset} with hedging error" do
      invalid_json = ~s({
        "new_claim": "Heat might flow from hot to cold in some cases",
        "inference_type": "deductive",
        "reasoning": "Test reasoning"
      })

      assert {:error, changeset} = Explorer.parse_response(invalid_json)
      refute changeset.valid?

      assert [new_claim: {"Hedging detected: must commit to extension without uncertainty", _}] =
               changeset.errors
    end

    test "hedging word 'possibly' returns error" do
      invalid_json = ~s({
        "new_claim": "This is possibly true",
        "inference_type": "inductive",
        "reasoning": "Test"
      })

      assert {:error, changeset} = Explorer.parse_response(invalid_json)
      refute changeset.valid?

      assert {_field, {error_msg, _}} =
               Enum.find(changeset.errors, fn {k, _} -> k == :new_claim end)

      assert String.contains?(error_msg, "Hedging detected")
    end

    test "hedging word 'perhaps' returns error" do
      invalid_json = ~s({
        "new_claim": "Perhaps this is true",
        "inference_type": "deductive",
        "reasoning": "Test"
      })

      assert {:error, changeset} = Explorer.parse_response(invalid_json)
      refute changeset.valid?

      assert {_field, {error_msg, _}} =
               Enum.find(changeset.errors, fn {k, _} -> k == :new_claim end)

      assert String.contains?(error_msg, "Hedging detected")
    end

    test "transitional prefix 'therefore' is stripped from claim" do
      json_with_prefix = ~s({
        "new_claim": "Therefore heat flows from hot to cold in isolated regions",
        "inference_type": "deductive",
        "reasoning": "Test reasoning"
      })

      assert {:ok, schema} = Explorer.parse_response(json_with_prefix)
      refute String.starts_with?(schema.new_claim, "Therefore")
      assert schema.new_claim == "Heat flows from hot to cold in isolated regions"
    end

    test "transitional prefix 'consequently' is stripped from claim" do
      json_with_prefix = ~s({
        "new_claim": "Consequently, entropy increases over time",
        "inference_type": "deductive",
        "reasoning": "Test"
      })

      assert {:ok, schema} = Explorer.parse_response(json_with_prefix)
      refute String.starts_with?(schema.new_claim, "Consequently")
      assert String.starts_with?(schema.new_claim, "E")
    end

    test "transitional prefix 'thus' is stripped from claim" do
      json_with_prefix = ~s({
        "new_claim": "Thus the system reaches equilibrium",
        "inference_type": "inductive",
        "reasoning": "Test"
      })

      assert {:ok, schema} = Explorer.parse_response(json_with_prefix)
      refute String.starts_with?(schema.new_claim, "Thus")
    end

    test "missing reasoning field defaults to empty string" do
      json_without_reasoning = ~s({
        "new_claim": "Test claim",
        "inference_type": "deductive"
      })

      assert {:ok, schema} = Explorer.parse_response(json_without_reasoning)
      assert schema.reasoning == ""
    end

    test "JSON with markdown code fences is handled correctly" do
      json_with_fences = """
      ```json
      {
        "new_claim": "Test claim",
        "inference_type": "deductive",
        "reasoning": "Test"
      }
      ```
      """

      assert {:ok, schema} = Explorer.parse_response(json_with_fences)
      assert schema.new_claim == "Test claim"
    end
  end

  describe "confidence_delta/1" do
    test "returns 0.10 for valid {:ok, schema} response" do
      schema = %Unshackled.Agents.Responses.ExplorerSchema{
        new_claim: "Test claim",
        inference_type: "deductive",
        reasoning: "Test"
      }

      assert Explorer.confidence_delta({:ok, schema}) == 0.10
    end

    test "returns 0.0 for invalid {:error, changeset} response" do
      schema = %Unshackled.Agents.Responses.ExplorerSchema{}
      changeset = Unshackled.Agents.Responses.ExplorerSchema.changeset(schema, %{})

      assert Explorer.confidence_delta({:error, changeset}) == 0.0
    end

    test "returns 0.10 for legacy map with valid: true" do
      assert Explorer.confidence_delta(%{valid: true, new_claim: "Test"}) == 0.10
    end

    test "returns 0.0 for legacy map with valid: false" do
      assert Explorer.confidence_delta(%{valid: false}) == 0.0
    end

    test "returns 0.0 for unexpected input" do
      assert Explorer.confidence_delta(nil) == 0.0
      assert Explorer.confidence_delta("string") == 0.0
      assert Explorer.confidence_delta([]) == 0.0
    end
  end

  describe "role/0" do
    test "returns :explorer" do
      assert Explorer.role() == :explorer
    end
  end

  describe "build_prompt/1" do
    test "builds a prompt with current claim and support strength" do
      blackboard = %Unshackled.Blackboard.Server{
        current_claim: "Test claim",
        support_strength: 0.75
      }

      prompt = Explorer.build_prompt(blackboard)

      assert String.contains?(prompt, "Test claim")
      assert String.contains?(prompt, "0.75")
      assert String.contains?(prompt, "deductive|inductive|abductive")
    end
  end
end
