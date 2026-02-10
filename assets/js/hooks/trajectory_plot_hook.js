import { parseChartData, getChartDimensions } from './utils/chart_data.js';
import { cleanupSvg, createTooltip, showTooltip, hideTooltip } from './utils/chart_dom.js';
import { TRANSITION_DURATION } from './utils/constants.js';

/**
 * TrajectoryPlotHook - D3 2D scatter plot for embedding space trajectory.
 *
 * Displays a scatter plot showing the trajectory of claims through the embedding space:
 * - X/Y from PCA-reduced embeddings
 * - Points connected with lines to show trajectory path
 * - Points colored by cycle number (gradient from start to current)
 * - Current position marked distinctly (larger point)
 *
 * Data format: [{cycle: 1, x: 0.5, y: -0.3}, {cycle: 2, x: 0.6, y: -0.1}, ...]
 *
 * Brutalist aesthetic: white points/lines on dark background.
 */
const TrajectoryPlotHook = {
  mounted() {
    this.isInitialRender = true;
    this.renderChart();
  },

  updated() {
    this.renderChart();
  },

  destroyed() {
    if (this.tooltip) {
      this.tooltip.remove();
    }
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

    // Empty state - need at least one point
    if (sortedData.length === 0) {
      if (!isUpdate) {
        const svg = d3
          .select(this.el)
          .append("svg")
          .attr("width", width)
          .attr("height", height)
          .attr("class", "trajectory-plot-svg");

        svg
          .append("text")
          .attr("x", width / 2)
          .attr("y", height / 2)
          .attr("text-anchor", "middle")
          .attr("fill", "#6b7280")
          .attr("font-family", "monospace")
          .text("No trajectory data yet");
      }
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

      // Animate gridlines
      const xTicks = newXScale.ticks(5);
      if (this.gridX) {
        this.gridX.selectAll("line")
          .data(xTicks)
          .transition()
          .duration(TRANSITION_DURATION)
          .attr("x1", (d) => newXScale(d))
          .attr("x2", (d) => newXScale(d));
      }

      const yTicks = newYScale.ticks(5);
      if (this.gridY) {
        this.gridY.selectAll("line")
          .data(yTicks)
          .transition()
          .duration(TRANSITION_DURATION)
          .attr("y1", (d) => newYScale(d))
          .attr("y2", (d) => newYScale(d));
      }

      // Animate axis rescaling
      if (this.xAxisG) {
        const xAxis = d3.axisBottom(newXScale).ticks(5);
        this.xAxisG.transition().duration(TRANSITION_DURATION).call(xAxis);
      }

      if (this.yAxisG) {
        const yAxis = d3.axisLeft(newYScale).ticks(5);
        this.yAxisG.transition().duration(TRANSITION_DURATION).call(yAxis);
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
      const gridColor = "#333333";

      // X gridlines
      const xTicks = xScale.ticks(5);
      this.gridX = g.append("g")
        .attr("class", "grid-x")
        .selectAll("line")
        .data(xTicks)
        .enter()
        .append("line")
        .attr("x1", (d) => xScale(d))
        .attr("x2", (d) => xScale(d))
        .attr("y1", 0)
        .attr("y2", innerHeight)
        .attr("stroke", gridColor)
        .attr("stroke-width", 1);

      // Y gridlines
      const yTicks = yScale.ticks(5);
      this.gridY = g.append("g")
        .attr("class", "grid-y")
        .selectAll("line")
        .data(yTicks)
        .enter()
        .append("line")
        .attr("x1", 0)
        .attr("x2", innerWidth)
        .attr("y1", (d) => yScale(d))
        .attr("y2", (d) => yScale(d))
        .attr("stroke", gridColor)
        .attr("stroke-width", 1);

    // Draw trajectory line connecting points (only if more than 1 point)
    if (sortedData.length > 1) {
      const line = d3
        .line()
        .x((d) => xScale(d.x))
        .y((d) => yScale(d.y))
        .curve(d3.curveLinear);

      if (isUpdate && this.trajectoryLine) {
        // Animate line extension
        this.trajectoryLine.datum(sortedData).transition().duration(TRANSITION_DURATION).attr("d", line);
      } else {
        this.trajectoryLine = g.append("path")
          .datum(sortedData)
          .attr("fill", "none")
          .attr("stroke", "#6b7280")
          .attr("stroke-width", 1.5)
          .attr("stroke-dasharray", "4,4")
          .attr("d", line);
      }
    } else if (this.trajectoryLine && sortedData.length === 1) {
      // Remove line if we went from multiple points to single point
      this.trajectoryLine.remove();
      this.trajectoryLine = null;
    }

    // Create or update tooltip
    if (!this.tooltip) {
      this.tooltip = createTooltip("trajectory-plot-tooltip");
    }
    const tooltip = this.tooltip;

    // Draw or update points
    const existingPoints = this.points ? this.points.data().map(d => d.cycle) : [];
    const newPoints = sortedData.filter(d => !existingPoints.includes(d.cycle));

    const points = g.selectAll(".trajectory-point")
      .data(sortedData, (d) => d.cycle);

    points.exit().remove();

    const pointsEnter = points.enter()
      .append("circle")
      .attr("class", "trajectory-point")
      .attr("cx", (d) => xScale(d.x))
      .attr("cy", (d) => yScale(d.y))
      .attr("r", (d, i) => (i === sortedData.length - 1 ? 8 : 5))
      .attr("fill", (d) => colorScale(d.cycle))
      .attr("stroke", "#ffffff")
      .attr("stroke-width", (d, i) => (i === sortedData.length - 1 ? 2 : 1))
      .style("cursor", "pointer");

    if (isUpdate) {
      // Fade in new points
      pointsEnter
        .attr("opacity", 0)
        .transition()
        .duration(TRANSITION_DURATION)
        .attr("opacity", 1);
    }

    this.points = pointsEnter.merge(points);

    // Update existing points' positions
    if (isUpdate) {
      this.points
        .transition()
        .duration(TRANSITION_DURATION)
        .attr("cx", (d) => xScale(d.x))
        .attr("cy", (d) => yScale(d.y))
        .attr("fill", (d) => colorScale(d.cycle))
        .attr("r", (d, i) => (i === sortedData.length - 1 ? 8 : 5))
        .attr("stroke-width", (d, i) => (i === sortedData.length - 1 ? 2 : 1));
    }

    // Setup event handlers for points
    this.points
      .on("mouseenter", function (event, d) {
        d3.select(this)
          .transition()
          .duration(100)
          .attr("r", d3.select(this).attr("r") * 1.5);

        const supportPct = d.support ? (d.support * 100).toFixed(1) + "%" : "N/A";
        const html = `
          <span class="font-bold">Cycle ${d.cycle}</span><br>
          Support: ${supportPct}<br>
          ${d.claim ? `<span class="text-gray-400">${d.claim.substring(0, 50)}${d.claim.length > 50 ? "..." : ""}</span>` : ""}
        `;
        showTooltip(tooltip, html, event);
      })
      .on("mouseleave", function (event, d) {
        const isLast = d.cycle === sortedData[sortedData.length - 1].cycle;
        d3.select(this)
          .transition()
          .duration(100)
          .attr("r", isLast ? 8 : 5);

        hideTooltip(tooltip);
      });

    // Mark current position with outer ring
    if (sortedData.length > 0) {
      const lastPoint = sortedData[sortedData.length - 1];
      if (isUpdate && this.currentPointMarker) {
        this.currentPointMarker
          .transition()
          .duration(TRANSITION_DURATION)
          .attr("cx", xScale(lastPoint.x))
          .attr("cy", yScale(lastPoint.y));
      } else {
        this.currentPointMarker = g.append("circle")
          .attr("cx", xScale(lastPoint.x))
          .attr("cy", yScale(lastPoint.y))
          .attr("r", 12)
          .attr("fill", "none")
          .attr("stroke", "#ffffff")
          .attr("stroke-width", 2);
      }
    }

    if (!isUpdate) {
      // X axis (only create on initial render)
      const xAxis = d3.axisBottom(xScale).ticks(5);

      this.xAxisG = g.append("g")
        .attr("transform", `translate(0,${innerHeight})`)
        .call(xAxis)
        .attr("color", "#9ca3af")
        .selectAll("text")
        .attr("fill", "#9ca3af")
        .attr("font-family", "monospace");

      // X axis label
      g.append("text")
        .attr("x", innerWidth / 2)
        .attr("y", innerHeight + 40)
        .attr("text-anchor", "middle")
        .attr("fill", "#6b7280")
        .attr("font-size", "12px")
        .attr("font-family", "monospace")
        .text("PC1");

      // Y axis (only create on initial render)
      const yAxis = d3.axisLeft(yScale).ticks(5);

      this.yAxisG = g.append("g")
        .call(yAxis)
        .attr("color", "#9ca3af")
        .selectAll("text")
        .attr("fill", "#9ca3af")
        .attr("font-family", "monospace");

      // Y axis label
      g.append("text")
        .attr("transform", "rotate(-90)")
        .attr("x", -innerHeight / 2)
        .attr("y", -45)
        .attr("text-anchor", "middle")
        .attr("fill", "#6b7280")
        .attr("font-size", "12px")
        .attr("font-family", "monospace")
        .text("PC2");

      // Legend for cycle gradient - positioned below chart
      const legendWidth = 100;
      const legendHeight = 10;
      const legendY = innerHeight + 10;
      const legendX = (innerWidth - legendWidth) / 2;

      // Gradient definition
      const defs = svg.append("defs");
      const gradient = defs
        .append("linearGradient")
        .attr("id", "trajectory-legend-gradient")
        .attr("x1", "0%")
        .attr("x2", "100%");

      gradient.append("stop").attr("offset", "0%").attr("stop-color", "#06b6d4");
      gradient.append("stop").attr("offset", "100%").attr("stop-color", "#ffffff");

      // Legend rect
      g.append("rect")
        .attr("x", legendX)
        .attr("y", legendY)
        .attr("width", legendWidth)
        .attr("height", legendHeight)
        .attr("fill", "url(#trajectory-legend-gradient)")
        .attr("stroke", "#ffffff")
        .attr("stroke-width", 1);

      // Legend labels
      g.append("text")
        .attr("x", legendX)
        .attr("y", legendY + legendHeight + 12)
        .attr("fill", "#6b7280")
        .attr("font-size", "10px")
        .attr("font-family", "monospace")
        .text(`C${cycleExtent[0]}`);

      g.append("text")
        .attr("x", legendX + legendWidth)
        .attr("y", legendY + legendHeight + 12)
        .attr("text-anchor", "end")
        .attr("fill", "#6b7280")
        .attr("font-size", "10px")
        .attr("font-family", "monospace")
        .text(`C${cycleExtent[1]}`);

      // Legend title - below the gradient bar
      g.append("text")
        .attr("x", legendX + legendWidth / 2)
        .attr("y", legendY - 3)
        .attr("text-anchor", "middle")
        .attr("fill", "#9ca3af")
        .attr("font-size", "10px")
        .attr("font-family", "monospace")
        .text("CYCLE");
    }
    }
    
    // Store references for updates
    this.svg = svg;
    this.g = g;
    this.isInitialRender = false;
  },
};

export { TrajectoryPlotHook };
