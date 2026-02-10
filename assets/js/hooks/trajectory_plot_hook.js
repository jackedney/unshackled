import { parseChartData, getChartDimensions } from './utils/chart_dom.js';
import { cleanupSvg, createTooltip, showTooltip, hideTooltip, applyTextStyle, escapeHtml } from './utils/chart_dom.js';
import { TRANSITION_DURATION } from './utils/colors.js';
import { renderLegend } from './utils/legend.js';
import { renderXAxis, renderYAxis, renderGridlines } from './utils/axes.js';

const TrajectoryPlotHook = {
  mounted() {
    this.isInitialRender = true;
    this.renderChart();
  },
  updated() { this.renderChart(); },
  destroyed() {
    this.tooltip?.remove();
    this.cleanup();
  },

  getData() {
    return parseChartData(this.el, 'chartData', []);
  },

  getConfig() {
    return getChartDimensions(this.el, {
      width: 500,
      height: 300,
      margin: { top: 30, right: 30, bottom: 50, left: 60 }
    });
  },

  cleanup() {
    cleanupSvg(this.el);
  },

  renderChart() {
    const data = this.getData();
    const config = this.getConfig();
    const { width, height, margin } = config;
    const innerWidth = width - margin.left - margin.right;
    const innerHeight = height - margin.top - margin.bottom;

    let svg, g, xScale, yScale, colorScale;
    const isUpdate = !this.isInitialRender;

    // Sort data by cycle number
    const sortedData = [...data].sort((a, b) => a.cycle - b.cycle);

    if (sortedData.length === 0) {
      if (!isUpdate) d3.select(this.el).append("svg").attr("width", width).attr("height", height).attr("class", "trajectory-plot-svg").append("text").attr("x", width / 2).attr("y", height / 2).attr("text-anchor", "middle").call(applyTextStyle, { fill: "#6b7280" }).text("No trajectory data yet");
      return;
    }

    // Calculate scales with padding
    const xExtent = d3.extent(sortedData, (d) => d.x);
    const yExtent = d3.extent(sortedData, (d) => d.y);
    const cycleExtent = d3.extent(sortedData, (d) => d.cycle);

    // Add padding to extents for better visualization
    const xPadding = (xExtent[1] - xExtent[0]) * 0.1 || 1;
    const yPadding = (yExtent[1] - yExtent[0]) * 0.1 || 1;

    const newXScale = d3
      .scaleLinear()
      .domain([xExtent[0] - xPadding, xExtent[1] + xPadding])
      .range([0, innerWidth]);

    const newYScale = d3
      .scaleLinear()
      .domain([yExtent[0] - yPadding, yExtent[1] + yPadding])
      .range([innerHeight, 0]);

    const newColorScale = d3
      .scaleLinear()
      .domain([cycleExtent[0], cycleExtent[1]])
      .range(["#06b6d4", "#ffffff"]);

    if (isUpdate && this.svg) {
      // Update existing chart with transitions
      svg = this.svg;
      g = this.g;

      const updateGridX = (grid, scale, ticks) => grid?.selectAll("line").data(ticks).transition().duration(TRANSITION_DURATION).attr("x1", d => scale(d)).attr("x2", d => scale(d));
      const updateGridY = (grid, scale, ticks) => grid?.selectAll("line").data(ticks).transition().duration(TRANSITION_DURATION).attr("y1", d => scale(d)).attr("y2", d => scale(d));
      updateGridX(this.gridX, newXScale, newXScale.ticks(5));
      updateGridY(this.gridY, newYScale, newYScale.ticks(5));
      if (this.xAxisG) {
        const xAxis = d3.axisBottom(newXScale).ticks(5);
        this.xAxisG.transition().duration(TRANSITION_DURATION).call(xAxis).attr("color", "#9ca3af").selectAll("text").call(applyTextStyle);
      }
      if (this.yAxisG) {
        const yAxis = d3.axisLeft(newYScale).ticks(5);
        this.yAxisG.transition().duration(TRANSITION_DURATION).call(yAxis).attr("color", "#9ca3af").selectAll("text").call(applyTextStyle);
      }

      xScale = newXScale;
      yScale = newYScale;
      colorScale = newColorScale;
    } else {
      // Initial render - no transitions
      this.cleanup();

      svg = d3
        .select(this.el)
        .append("svg")
        .attr("width", width)
        .attr("height", height)
        .attr("class", "trajectory-plot-svg");

      // Single point renders as dot without line
      g = svg
        .append("g")
        .attr("transform", `translate(${margin.left},${margin.top})`);

      xScale = newXScale;
      yScale = newYScale;
      colorScale = newColorScale;

      // Gridlines - brutalist sharp style
      this.gridX = renderGridlines(g, xScale, {
        orientation: 'vertical',
        tickCount: 5,
        innerHeight
      });

      this.gridY = renderGridlines(g, yScale, {
        orientation: 'horizontal',
        tickCount: 5,
        innerWidth
      });
    }

    if (sortedData.length > 1) {
      const line = d3.line().x(d => xScale(d.x)).y(d => yScale(d.y)).curve(d3.curveLinear);
      if (isUpdate && this.trajectoryLine) {
        this.trajectoryLine.datum(sortedData).transition().duration(TRANSITION_DURATION).attr("d", line);
      } else {
        this.trajectoryLine = g.append("path").datum(sortedData).attr("fill", "none").attr("stroke", "#6b7280").attr("stroke-width", 1.5).attr("stroke-dasharray", "4,4").attr("d", line);
      }
    } else if (this.trajectoryLine && sortedData.length === 1) {
      this.trajectoryLine.remove();
      this.trajectoryLine = null;
    }

    if (!this.tooltip) this.tooltip = createTooltip("trajectory-plot-tooltip");
    const tooltip = this.tooltip;
    const existingPoints = this.points ? this.points.data().map(d => d.cycle) : [];
    const newPoints = sortedData.filter(d => !existingPoints.includes(d.cycle));

    const points = g.selectAll(".trajectory-point").data(sortedData, d => d.cycle);
    points.exit().remove();

    const pointsEnter = points.enter()
      .append("circle")
      .attr("class", "trajectory-point")
      .attr("cx", d => xScale(d.x))
      .attr("cy", d => yScale(d.y))
      .attr("r", (d, i) => (i === sortedData.length - 1 ? 8 : 5))
      .attr("fill", d => colorScale(d.cycle))
      .attr("stroke", "#ffffff")
      .attr("stroke-width", (d, i) => (i === sortedData.length - 1 ? 2 : 1))
      .style("cursor", "pointer");

    if (isUpdate) {
      pointsEnter.attr("opacity", 0).transition().duration(TRANSITION_DURATION).attr("opacity", 1);
    }

    this.points = pointsEnter.merge(points);

    if (isUpdate) {
      this.points.transition().duration(TRANSITION_DURATION).attr("cx", d => xScale(d.x)).attr("cy", d => yScale(d.y)).attr("fill", d => colorScale(d.cycle)).attr("r", (d, i) => (i === sortedData.length - 1 ? 8 : 5)).attr("stroke-width", (d, i) => (i === sortedData.length - 1 ? 2 : 1));
    }

    this.points.on("mouseenter", function (event, d) {
      d3.select(this).transition().duration(100).attr("r", d3.select(this).attr("r") * 1.5);
      const supportPct = d.support ? (d.support * 100).toFixed(1) + "%" : "N/A";
      const claimText = d.claim ? escapeHtml(d.claim.substring(0, 50)) + (d.claim.length > 50 ? "..." : "") : "";
      showTooltip(tooltip, `<span class="font-bold">Cycle ${d.cycle}</span><br>Support: ${supportPct}<br>${claimText ? `<span class="text-gray-400">${claimText}</span>` : ""}`, event);
    }).on("mouseleave", function (event, d) {
      const isLast = d.cycle === sortedData[sortedData.length - 1].cycle;
      d3.select(this).transition().duration(100).attr("r", isLast ? 8 : 5);
      hideTooltip(tooltip);
    });

    if (sortedData.length) {
      const lastPoint = sortedData[sortedData.length - 1];
      if (isUpdate && this.currentPointMarker) {
        this.currentPointMarker.transition().duration(TRANSITION_DURATION).attr("cx", xScale(lastPoint.x)).attr("cy", yScale(lastPoint.y));
      } else {
        this.currentPointMarker = g.append("circle").attr("cx", xScale(lastPoint.x)).attr("cy", yScale(lastPoint.y)).attr("r", 12).attr("fill", "none").attr("stroke", "#ffffff").attr("stroke-width", 2);
      }
    }

    if (!isUpdate) {
      // X axis (only create on initial render)
      this.xAxisG = renderXAxis(g, xScale, {
        tickCount: 5,
        innerHeight,
        innerWidth,
        label: "PC1",
        labelOffset: 40
      });

      // Y axis (only create on initial render)
      this.yAxisG = renderYAxis(g, yScale, {
        tickCount: 5,
        innerHeight,
        label: "PC2",
        labelOffset: 45
      });

      const legendWidth = 100, legendHeight = 10, legendY = innerHeight + 10, legendX = (innerWidth - legendWidth) / 2;
      renderLegend(g, {
        startColor: '#06b6d4', endColor: '#ffffff', startLabel: `C${cycleExtent[0]}`, endLabel: `C${cycleExtent[1]}`, title: 'CYCLE',
      }, {
        position: { x: legendX, y: legendY },
        type: 'gradient',
        gradientSize: { width: legendWidth, height: legendHeight },
        labelStyle: { fill: '#6b7280', 'font-family': 'monospace', 'font-size': '10px' },
      });
    }

    // Store references for updates
    this.svg = svg;
    this.g = g;
    this.isInitialRender = false;
  },
};

export { TrajectoryPlotHook };
