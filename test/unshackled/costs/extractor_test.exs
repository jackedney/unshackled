defmodule Unshackled.Costs.ExtractorTest do
  use ExUnit.Case, async: true

  alias Unshackled.Costs.Extractor

  describe "extract_cost_data/1" do
    test "extracts complete cost data from ExLLM response struct" do
      response = %ExLLM.Types.LLMResponse{
        content: "Hello, world!",
        model: "openai/gpt-5.2",
        usage: %{
          input_tokens: 100,
          output_tokens: 50
        },
        cost: %{
          total_cost: 0.0015,
          input_cost: 0.0001,
          output_cost: 0.0014,
          currency: "USD"
        },
        finish_reason: "stop",
        id: "chatcmpl-xxx"
      }

      assert {:ok, cost_data} = Extractor.extract_cost_data(response)
      assert cost_data.input_tokens == 100
      assert cost_data.output_tokens == 50
      assert cost_data.cost_usd == 0.0015
    end

    test "extracts data from response with only usage, no cost" do
      response = %ExLLM.Types.LLMResponse{
        content: "Hello",
        usage: %{
          input_tokens: 75,
          output_tokens: 25
        }
      }

      assert {:ok, cost_data} = Extractor.extract_cost_data(response)
      assert cost_data.input_tokens == 75
      assert cost_data.output_tokens == 25
      assert cost_data.cost_usd == 0.0
    end

    test "extracts data from response with only cost, no usage" do
      response = %ExLLM.Types.LLMResponse{
        content: "Hello",
        cost: %{
          total_cost: 0.0020
        }
      }

      assert {:ok, cost_data} = Extractor.extract_cost_data(response)
      assert cost_data.input_tokens == 0
      assert cost_data.output_tokens == 0
      assert cost_data.cost_usd == 0.0020
    end

    test "handles nil response gracefully" do
      assert {:ok, cost_data} = Extractor.extract_cost_data(nil)
      assert cost_data.input_tokens == 0
      assert cost_data.output_tokens == 0
      assert cost_data.cost_usd == 0.0
    end

    test "handles response with no usage or cost" do
      response = %ExLLM.Types.LLMResponse{
        content: "Hello"
      }

      assert {:ok, cost_data} = Extractor.extract_cost_data(response)
      assert cost_data.input_tokens == 0
      assert cost_data.output_tokens == 0
      assert cost_data.cost_usd == 0.0
    end

    test "handles plain map with usage data" do
      response = %{
        usage: %{
          input_tokens: 200,
          output_tokens: 100
        },
        cost: %{
          total_cost: 0.0030
        }
      }

      assert {:ok, cost_data} = Extractor.extract_cost_data(response)
      assert cost_data.input_tokens == 200
      assert cost_data.output_tokens == 100
      assert cost_data.cost_usd == 0.0030
    end

    test "handles map with string keys" do
      response = %{
        "usage" => %{
          "input_tokens" => 150,
          "output_tokens" => 75
        },
        "cost" => %{
          "total_cost" => 0.00225
        }
      }

      assert {:ok, cost_data} = Extractor.extract_cost_data(response)
      assert cost_data.input_tokens == 150
      assert cost_data.output_tokens == 75
      assert cost_data.cost_usd == 0.00225
    end

    test "handles empty map" do
      assert {:ok, cost_data} = Extractor.extract_cost_data(%{})
      assert cost_data.input_tokens == 0
      assert cost_data.output_tokens == 0
      assert cost_data.cost_usd == 0.0
    end

    test "handles response with nil usage" do
      response = %ExLLM.Types.LLMResponse{
        content: "Hello",
        usage: nil
      }

      assert {:ok, cost_data} = Extractor.extract_cost_data(response)
      assert cost_data.input_tokens == 0
      assert cost_data.output_tokens == 0
      assert cost_data.cost_usd == 0.0
    end

    test "handles response with nil cost" do
      response = %ExLLM.Types.LLMResponse{
        content: "Hello",
        usage: %{
          input_tokens: 50,
          output_tokens: 25
        },
        cost: nil
      }

      assert {:ok, cost_data} = Extractor.extract_cost_data(response)
      assert cost_data.input_tokens == 50
      assert cost_data.output_tokens == 25
      assert cost_data.cost_usd == 0.0
    end

    test "handles zero token counts" do
      response = %ExLLM.Types.LLMResponse{
        content: "Hello",
        usage: %{
          input_tokens: 0,
          output_tokens: 0
        },
        cost: %{
          total_cost: 0.0
        }
      }

      assert {:ok, cost_data} = Extractor.extract_cost_data(response)
      assert cost_data.input_tokens == 0
      assert cost_data.output_tokens == 0
      assert cost_data.cost_usd == 0.0
    end

    test "handles negative values by using zero (graceful degradation)" do
      response = %ExLLM.Types.LLMResponse{
        content: "Hello",
        usage: %{
          input_tokens: -10,
          output_tokens: -5
        },
        cost: %{
          total_cost: -0.001
        }
      }

      assert {:ok, cost_data} = Extractor.extract_cost_data(response)
      assert cost_data.input_tokens == 0
      assert cost_data.output_tokens == 0
      assert cost_data.cost_usd == 0.0
    end

    test "handles very large token counts" do
      response = %ExLLM.Types.LLMResponse{
        content: "Hello",
        usage: %{
          input_tokens: 100_000,
          output_tokens: 50_000
        },
        cost: %{
          total_cost: 1.50
        }
      }

      assert {:ok, cost_data} = Extractor.extract_cost_data(response)
      assert cost_data.input_tokens == 100_000
      assert cost_data.output_tokens == 50_000
      assert cost_data.cost_usd == 1.50
    end

    test "handles float token counts by converting" do
      response = %ExLLM.Types.LLMResponse{
        content: "Hello",
        usage: %{
          input_tokens: 100.5,
          output_tokens: 50.7
        },
        cost: %{
          total_cost: 0.0025
        }
      }

      assert {:ok, cost_data} = Extractor.extract_cost_data(response)
      assert cost_data.input_tokens == 100
      assert cost_data.output_tokens == 50
      assert cost_data.cost_usd == 0.0025
    end

    test "returns always :ok tuple for non-map input" do
      assert {:ok, cost_data} = Extractor.extract_cost_data("string")
      assert cost_data.input_tokens == 0
      assert cost_data.output_tokens == 0
      assert cost_data.cost_usd == 0.0

      assert {:ok, cost_data} = Extractor.extract_cost_data(123)
      assert cost_data.input_tokens == 0
      assert cost_data.output_tokens == 0
      assert cost_data.cost_usd == 0.0

      assert {:ok, cost_data} = Extractor.extract_cost_data([])
      assert cost_data.input_tokens == 0
      assert cost_data.output_tokens == 0
      assert cost_data.cost_usd == 0.0
    end
  end
end
