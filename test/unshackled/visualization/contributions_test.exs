defmodule Unshackled.Visualization.ContributionsTest do
  use ExUnit.Case, async: true

  alias Unshackled.Agents.AgentContribution
  alias Unshackled.Visualization.Contributions
  alias Unshackled.Repo

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "plot_agent_pie/1" do
    test "returns empty plot when blackboard_id is not positive integer" do
      result = Contributions.plot_agent_pie(0)
      assert {:error, "blackboard_id must be a positive integer"} = result

      result = Contributions.plot_agent_pie(-1)
      assert {:error, "blackboard_id must be a positive integer"} = result

      result = Contributions.plot_agent_pie("invalid")
      assert {:error, "blackboard_id must be a positive integer"} = result
    end

    test "returns empty plot when no contributions exist" do
      result = Contributions.plot_agent_pie(999)
      assert {:ok, spec} = result
      assert spec["mark"] == "text"
      assert length(spec["data"]["values"]) == 1
      assert hd(spec["data"]["values"])["text"] == "No contributions data"
    end

    test "returns empty plot when only rejected contributions exist" do
      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 1,
        agent_role: "explorer",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "test output",
        accepted: false,
        support_delta: 0.1
      })

      result = Contributions.plot_agent_pie(1)
      assert {:ok, spec} = result
      assert spec["mark"] == "text"
      assert hd(spec["data"]["values"])["text"] == "No contributions data"
    end

    test "creates pie chart with accepted contributions by agent role" do
      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 1,
        agent_role: "explorer",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output 1",
        accepted: true,
        support_delta: 0.1
      })

      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 2,
        agent_role: "critic",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output 2",
        accepted: true,
        support_delta: -0.15
      })

      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 3,
        agent_role: "connector",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output 3",
        accepted: true,
        support_delta: 0.05
      })

      result = Contributions.plot_agent_pie(1)
      assert {:ok, spec} = result
      assert spec["$schema"] == "https://vega.github.io/schema/vega-lite/v5.json"
      assert spec["width"] == 1200
      assert spec["height"] == 500
      assert is_list(spec["concat"])
    end

    test "calculates correct percentages for contributions" do
      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 1,
        agent_role: "explorer",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output 1",
        accepted: true,
        support_delta: 0.1
      })

      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 2,
        agent_role: "explorer",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output 2",
        accepted: true,
        support_delta: 0.1
      })

      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 3,
        agent_role: "critic",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output 3",
        accepted: true,
        support_delta: -0.15
      })

      result = Contributions.plot_agent_pie(1)
      assert {:ok, spec} = result

      pie_chart = hd(spec["concat"])
      data_values = pie_chart["data"]["values"]

      explorer_data = Enum.find(data_values, &(&1.agent_role == "explorer"))
      critic_data = Enum.find(data_values, &(&1.agent_role == "critic"))

      assert explorer_data != nil
      assert explorer_data.count == 2
      assert explorer_data.percentage == 66.7

      assert critic_data != nil
      assert critic_data.count == 1
      assert critic_data.percentage == 33.3
    end

    test "creates example: Explorer 30%, Critic 25%, Connector 15%, etc." do
      contributions = [
        {3, "explorer", 0.1},
        {3, "critic", -0.15},
        {2, "connector", 0.05},
        {1, "steelman", -0.05},
        {1, "quantifier", 0.05}
      ]

      Enum.each(contributions, fn {count, role, delta} ->
        Enum.each(1..count, fn i ->
          insert_contribution(%{
            blackboard_id: 1,
            cycle_number: i,
            agent_role: role,
            model_used: "gpt-4",
            input_prompt: "test",
            output_text: "output",
            accepted: true,
            support_delta: delta
          })
        end)
      end)

      result = Contributions.plot_agent_pie(1)
      assert {:ok, spec} = result

      pie_chart = hd(spec["concat"])
      data_values = pie_chart["data"]["values"]

      explorer_data = Enum.find(data_values, &(&1.agent_role == "explorer"))
      critic_data = Enum.find(data_values, &(&1.agent_role == "critic"))
      connector_data = Enum.find(data_values, &(&1.agent_role == "connector"))

      assert explorer_data != nil
      assert explorer_data.percentage == 30.0

      assert critic_data != nil
      assert critic_data.percentage == 30.0

      assert connector_data != nil
      assert connector_data.percentage == 20.0
    end

    test "calculates correct net confidence delta for bar chart" do
      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 1,
        agent_role: "explorer",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output 1",
        accepted: true,
        support_delta: 0.1
      })

      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 2,
        agent_role: "explorer",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output 2",
        accepted: true,
        support_delta: 0.1
      })

      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 3,
        agent_role: "critic",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output 3",
        accepted: true,
        support_delta: -0.15
      })

      result = Contributions.plot_agent_pie(1)
      assert {:ok, spec} = result

      bar_chart = List.last(spec["concat"])
      data_values = bar_chart["data"]["values"]

      explorer_data = Enum.find(data_values, &(&1.agent_role == "explorer"))
      critic_data = Enum.find(data_values, &(&1.agent_role == "critic"))

      assert explorer_data != nil
      assert explorer_data.net_delta == 0.2

      assert critic_data != nil
      assert critic_data.net_delta == -0.15
    end

    test "bar chart shows net confidence delta by agent role" do
      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 1,
        agent_role: "explorer",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output",
        accepted: true,
        support_delta: 0.1
      })

      result = Contributions.plot_agent_pie(1)
      assert {:ok, spec} = result

      bar_chart = List.last(spec["concat"])
      assert bar_chart["title"]["text"] == "Net Confidence Delta by Role"
      assert bar_chart["mark"]["type"] == "bar"
      assert bar_chart["encoding"]["y"]["field"] == "net_delta"
      assert bar_chart["encoding"]["x"]["field"] == "agent_role"
    end

    test "pie chart title is 'Accepted Contributions by Role'" do
      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 1,
        agent_role: "explorer",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output",
        accepted: true,
        support_delta: 0.1
      })

      result = Contributions.plot_agent_pie(1)
      assert {:ok, spec} = result

      pie_chart = hd(spec["concat"])
      assert pie_chart["title"]["text"] == "Accepted Contributions by Role"
    end

    test "pie chart uses theta encoding for percentage" do
      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 1,
        agent_role: "explorer",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output",
        accepted: true,
        support_delta: 0.1
      })

      result = Contributions.plot_agent_pie(1)
      assert {:ok, spec} = result

      pie_chart = hd(spec["concat"])
      assert pie_chart["encoding"]["theta"]["field"] == "percentage"
      assert pie_chart["encoding"]["theta"]["type"] == "quantitative"
      assert pie_chart["encoding"]["theta"]["stack"] == true
    end

    test "pie chart uses color encoding for agent role" do
      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 1,
        agent_role: "explorer",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output",
        accepted: true,
        support_delta: 0.1
      })

      result = Contributions.plot_agent_pie(1)
      assert {:ok, spec} = result

      pie_chart = hd(spec["concat"])
      assert pie_chart["encoding"]["color"]["field"] == "agent_role"
      assert pie_chart["encoding"]["color"]["type"] == "nominal"
    end

    test "includes tooltips with agent role, count, and percentage" do
      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 1,
        agent_role: "explorer",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output",
        accepted: true,
        support_delta: 0.1
      })

      result = Contributions.plot_agent_pie(1)
      assert {:ok, spec} = result

      pie_chart = hd(spec["concat"])
      tooltip = pie_chart["encoding"]["tooltip"]
      assert length(tooltip) == 3
      assert Enum.any?(tooltip, fn t -> t["title"] == "Agent Role" end)
      assert Enum.any?(tooltip, fn t -> t["title"] == "Count" end)
      assert Enum.any?(tooltip, fn t -> t["title"] == "Percentage" end)
    end

    test "includes tooltips in bar chart with agent role, net delta, and count" do
      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 1,
        agent_role: "explorer",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output",
        accepted: true,
        support_delta: 0.1
      })

      result = Contributions.plot_agent_pie(1)
      assert {:ok, spec} = result

      bar_chart = List.last(spec["concat"])
      tooltip = bar_chart["encoding"]["tooltip"]
      assert length(tooltip) == 3
      assert Enum.any?(tooltip, fn t -> t["title"] == "Agent Role" end)
      assert Enum.any?(tooltip, fn t -> t["title"] == "Net Delta" end)
      assert Enum.any?(tooltip, fn t -> t["title"] == "Count" end)
    end

    test "handles contributions with nil support_delta" do
      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 1,
        agent_role: "explorer",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output",
        accepted: true,
        support_delta: 0.1
      })

      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 2,
        agent_role: "critic",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output",
        accepted: true,
        support_delta: nil
      })

      result = Contributions.plot_agent_pie(1)
      assert {:ok, spec} = result

      bar_chart = List.last(spec["concat"])
      data_values = bar_chart["data"]["values"]

      critic_data = Enum.find(data_values, &(&1.agent_role == "critic"))
      assert critic_data != nil
      assert critic_data.net_delta == 0.0
    end

    test "queries only contributions for specified blackboard_id" do
      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 1,
        agent_role: "explorer",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output",
        accepted: true,
        support_delta: 0.1
      })

      insert_contribution(%{
        blackboard_id: 2,
        cycle_number: 1,
        agent_role: "critic",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output",
        accepted: true,
        support_delta: -0.15
      })

      result_1 = Contributions.plot_agent_pie(1)
      assert {:ok, spec_1} = result_1

      pie_chart_1 = hd(spec_1["concat"])
      data_values_1 = pie_chart_1["data"]["values"]
      assert length(data_values_1) == 1
      assert hd(data_values_1).agent_role == "explorer"

      result_2 = Contributions.plot_agent_pie(2)
      assert {:ok, spec_2} = result_2

      pie_chart_2 = hd(spec_2["concat"])
      data_values_2 = pie_chart_2["data"]["values"]
      assert length(data_values_2) == 1
      assert hd(data_values_2).agent_role == "critic"
    end

    test "concat layout contains both pie and bar charts" do
      insert_contribution(%{
        blackboard_id: 1,
        cycle_number: 1,
        agent_role: "explorer",
        model_used: "gpt-4",
        input_prompt: "test",
        output_text: "output",
        accepted: true,
        support_delta: 0.1
      })

      result = Contributions.plot_agent_pie(1)
      assert {:ok, spec} = result

      assert is_list(spec["concat"])
      assert length(spec["concat"]) == 2

      pie_chart = hd(spec["concat"])
      bar_chart = List.last(spec["concat"])

      assert pie_chart["mark"]["type"] == "arc"
      assert bar_chart["mark"]["type"] == "bar"
    end
  end

  defp insert_contribution(attrs) do
    %AgentContribution{}
    |> AgentContribution.changeset(attrs)
    |> Repo.insert!()
  end
end
