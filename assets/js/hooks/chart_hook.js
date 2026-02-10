/**
 * Base ChartHook for D3.js integration with LiveView.
 *
 * This hook provides a foundation for rendering D3 charts that receive
 * data via the data-chart-data attribute and update reactively when
 * LiveView pushes new data.
 *
 * Usage in HEEx:
 *   <div id="my-chart" phx-hook="ChartHook" data-chart-data={Jason.encode!(@chart_data)}></div>
 */
const ChartHook = {
  mounted() {
    this.chart = null;
    this.renderChart();
  },

  updated() {
    this.renderChart();
  },

  destroyed() {
    this.cleanup();
  },

  /**
   * Parse chart data from the data-chart-data attribute.
   * Returns empty array if data is missing or invalid.
   */
  getData() {
    const dataAttr = this.el.dataset.chartData;

    if (!dataAttr) {
      console.warn("ChartHook: Missing data-chart-data attribute on element", this.el.id);
      return [];
    }

    try {
      return JSON.parse(dataAttr);
    } catch (e) {
      console.warn("ChartHook: Failed to parse chart data", e);
      return [];
    }
  },

  getConfig() {
    const margin = (side) => parseInt(this.el.dataset[`chartMargin${side.charAt(0).toUpperCase() + side.slice(1)}`]);
    return {
      width: parseInt(this.el.dataset.chartWidth) || this.el.clientWidth || 400,
      height: parseInt(this.el.dataset.chartHeight) || 200,
      margin: { top: margin('top') || 20, right: margin('right') || 20, bottom: margin('bottom') || 30, left: margin('left') || 40 }
    };
  },

  /**
   * Render the chart. Override in specific chart implementations.
   * Base implementation renders a placeholder message.
   */
  renderChart() {
    const data = this.getData();
    const config = this.getConfig();

    this.cleanup();

    const svg = d3.select(this.el)
      .append("svg")
      .attr("width", config.width)
      .attr("height", config.height)
      .attr("class", "chart-svg");

    if (data.length === 0) {
      svg.append("text")
        .attr("x", config.width / 2)
        .attr("y", config.height / 2)
        .attr("text-anchor", "middle")
        .attr("fill", "#6b7280")
        .text("No data available");
      return;
    }

    this.chart = svg;
  },

  /**
   * Clean up existing chart before re-render.
   */
  cleanup() {
    d3.select(this.el).selectAll("svg").remove();
    this.chart = null;
  }
};

export { ChartHook };
