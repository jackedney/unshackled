defmodule UnshackledWeb.CoreComponentsTest do
  use UnshackledWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Phoenix.Component

  alias UnshackledWeb.CoreComponents

  describe "sparkline/1" do
    test "renders upward trending line with positive data" do
      assigns = %{
        data: [10, 15, 12, 18, 20],
        width: 100,
        height: 30,
        color: "#00ff00"
      }

      html = rendered_to_string(~H(<CoreComponents.sparkline {assigns} />))

      assert html =~ "<svg"
      assert html =~ "width=\"100\""
      assert html =~ "height=\"30\""
      assert html =~ "stroke=\"#00ff00\""
      assert html =~ "stroke-width=\"2\""
      assert html =~ "<path"
    end

    test "renders horizontal line with single data point" do
      assigns = %{
        data: [42],
        width: 80,
        height: 20,
        color: "#0088ff"
      }

      html = rendered_to_string(~H(<CoreComponents.sparkline {assigns} />))

      assert html =~ "<svg"
      assert html =~ "<path"
      # Single point renders horizontal line at middle height
      assert html =~ "M 0 10"
      assert html =~ "L 80 10"
    end

    test "renders correctly with 10 data points" do
      assigns = %{
        data: [5, 8, 6, 9, 7, 10, 8, 12, 9, 11],
        width: 100,
        height: 30,
        color: "#ff0000"
      }

      html = rendered_to_string(~H(<CoreComponents.sparkline {assigns} />))

      assert html =~ "<svg"
      assert html =~ "<path"
      assert html =~ "M 0"
      assert html =~ "L 100"
    end

    test "renders empty SVG with empty data list" do
      assigns = %{
        data: [],
        width: 100,
        height: 30,
        color: "#00ff00"
      }

      html = rendered_to_string(~H(<CoreComponents.sparkline {assigns} />))

      assert html =~ "<svg"
      # Empty data should render empty path
      assert html =~ "d=\"\""
    end

    test "uses default width and height when not specified" do
      assigns = %{
        data: [1, 2, 3],
        color: "#00ff00"
      }

      html = rendered_to_string(~H(<CoreComponents.sparkline {assigns} />))

      assert html =~ "width=\"100\""
      assert html =~ "height=\"30\""
    end

    test "uses default color when not specified" do
      assigns = %{
        data: [1, 2, 3]
      }

      html = rendered_to_string(~H(<CoreComponents.sparkline {assigns} />))

      assert html =~ "stroke=\"#00ff00\""
    end

    test "handles negative numbers in data" do
      assigns = %{
        data: [-5, -2, 0, 3, -1],
        width: 100,
        height: 30,
        color: "#00ff00"
      }

      html = rendered_to_string(~H(<CoreComponents.sparkline {assigns} />))

      assert html =~ "<svg"
      assert html =~ "<path"
      assert html =~ "M 0"
    end

    test "handles same value for all data points" do
      assigns = %{
        data: [10, 10, 10, 10],
        width: 100,
        height: 30,
        color: "#00ff00"
      }

      html = rendered_to_string(~H(<CoreComponents.sparkline {assigns} />))

      assert html =~ "<svg"
      assert html =~ "<path"
      # All same values should still render a line
      assert html =~ "M 0"
    end

    test "renders downward trending line" do
      assigns = %{
        data: [20, 18, 15, 12, 10],
        width: 100,
        height: 30,
        color: "#ff0000"
      }

      html = rendered_to_string(~H(<CoreComponents.sparkline {assigns} />))

      assert html =~ "<svg"
      assert html =~ "<path"
    end

    test "applies custom CSS class" do
      assigns = %{
        data: [1, 2, 3],
        class: "custom-class"
      }

      html = rendered_to_string(~H(<CoreComponents.sparkline {assigns} />))

      assert html =~ "custom-class"
    end
  end
end
