import { parseChartData, getChartDimensions } from './utils/chart_data.js';
import { cleanupSvg, createTooltip, showTooltip, hideTooltip } from './utils/chart_dom.js';
import { supportToColor } from './utils/colors.js';
import { TRANSITION_DURATION, DEATH_THRESHOLD, GRADUATION_THRESHOLD } from './utils/constants.js';
import { renderXAxis, renderYAxis, renderGridlines, renderThresholdLine } from './utils/axes.js';

/**
 * SupportTimelineHook - D3 line chart for support strength over cycles.
 *
 * Displays a line chart with:
 * - X-axis: cycle number
 * - Y-axis: support strength (0-1)
 * - Horizontal reference lines at 0.2 (death threshold, red) and 0.85 (graduation, blue)
 * - Vertical markers at cycles where claim changed
 * - Tooltips showing claim text at each point
 * - Brutalist aesthetic: white line on dark background, sharp gridlines
 *
 * Data format: {
 *   support_timeline: [{cycle: 1, support: 0.5, claim_text: "..."}, ...],
 *   claim_transitions: [{to_cycle: 3, change_type: "refinement", trigger_agent: "operationalizer", ...}, ...]
 * }
 */
const SupportTimelineHook = {
  mounted() {
    this.isInitialRender = true;
    this.tooltip = null;
    this.renderChart();
  },

  updated() {
    this.renderChart();
  },

  destroyed() {
    this.cleanup();
  },

  getData() {
    const parsed = parseChartData(this.el, 'chartData', null);

    if (!parsed) {
      return { support_timeline: [], claim_transitions: [] };
    }

    if (Array.isArray(parsed)) {
      return { support_timeline: parsed, claim_transitions: [] };
    }

    return {
      support_timeline: parsed.support_timeline || [],
      claim_transitions: parsed.claim_transitions || []
    };
  },

  getConfig() {
    return getChartDimensions(this.el, {
      width: 600,
      height: 250,
      margin: { top: 20, right: 30, bottom: 40, left: 50 }
    });
  },

  cleanup() {
    cleanupSvg(this.el);
  },

  renderChart() {
    const { support_timeline: data, claim_transitions } = this.getData();
    const config = this.getConfig();
    const { width, height, margin } = config;
    const innerWidth = width - margin.left - margin.right;
    const innerHeight = height - margin.top - margin.bottom;

    let svg, g, xScale, yScale;
    const isUpdate = !this.isInitialRender;

    // Scales
    const xExtent = d3.extent(data, (d) => d.cycle);
    const newXScale = d3
      .scaleLinear()
      .domain([xExtent[0], Math.max(xExtent[1], xExtent[0] + 1)])
      .range([0, innerWidth]);

    const newYScale = d3.scaleLinear().domain([0, 1]).range([innerHeight, 0]);

    if (isUpdate && this.svg) {
      // Update existing chart with transitions
      svg = this.svg;
      g = this.g;

      // Animate axis rescaling
      if (this.xAxisG) {
        const xAxis = d3
          .axisBottom(newXScale)
          .ticks(Math.min(data.length, 10))
          .tickFormat(d3.format("d"));
        this.xAxisG.transition().duration(TRANSITION_DURATION).call(xAxis)
          .attr("color", "#9ca3af")
          .selectAll("text")
          .attr("fill", "#9ca3af")
          .attr("font-family", "monospace");
      }

      if (this.yAxisG) {
        const yAxis = d3.axisLeft(newYScale).ticks(5).tickFormat(d3.format(".0%"));
        this.yAxisG.transition().duration(TRANSITION_DURATION).call(yAxis)
          .attr("color", "#9ca3af")
          .selectAll("text")
          .attr("fill", "#9ca3af")
          .attr("font-family", "monospace");
      }

      // Animate threshold lines
      if (this.deathThreshold) {
        this.deathThreshold.transition().duration(TRANSITION_DURATION).attr("y1", newYScale(DEATH_THRESHOLD)).attr("y2", newYScale(DEATH_THRESHOLD));
        if (this.deathLabel) {
          this.deathLabel.transition().duration(TRANSITION_DURATION).attr("y", newYScale(DEATH_THRESHOLD));
        }
      }
      if (this.gradThreshold) {
        this.gradThreshold.transition().duration(TRANSITION_DURATION).attr("y1", newYScale(GRADUATION_THRESHOLD)).attr("y2", newYScale(GRADUATION_THRESHOLD));
        if (this.gradLabel) {
          this.gradLabel.transition().duration(TRANSITION_DURATION).attr("y", newYScale(GRADUATION_THRESHOLD));
        }
      }

      xScale = newXScale;
      yScale = newYScale;
    } else {
      // Initial render - no transitions
      this.cleanup();

      svg = d3
        .select(this.el)
        .append("svg")
        .attr("width", width)
        .attr("height", height)
        .attr("class", "support-timeline-svg");

      // Empty state
      if (data.length === 0) {
        svg
          .append("text")
          .attr("x", width / 2)
          .attr("y", height / 2)
          .attr("text-anchor", "middle")
          .attr("fill", "#6b7280")
          .attr("font-family", "monospace")
          .text("No data yet");
        return;
      }

      g = svg
        .append("g")
        .attr("transform", `translate(${margin.left},${margin.top})`);

      xScale = newXScale;
      yScale = newYScale;

      // Gridlines - brutalist sharp style
      renderGridlines(g, yScale, {
        orientation: 'horizontal',
        values: [0, 0.2, 0.4, 0.6, 0.8, 1.0],
        innerWidth
      });

      // Death threshold line (0.2) - red
      const deathThreshold = renderThresholdLine(g, yScale, DEATH_THRESHOLD, {
        label: "DEATH",
        color: "#ef4444",
        strokeWidth: 2,
        dashArray: "5,5",
        innerWidth
      });
      this.deathThreshold = deathThreshold.line;
      this.deathLabel = deathThreshold.label;

      // Graduation threshold line (0.85) - blue
      const gradThreshold = renderThresholdLine(g, yScale, GRADUATION_THRESHOLD, {
        label: "GRAD",
        color: "#3b82f6",
        strokeWidth: 2,
        dashArray: "5,5",
        innerWidth
      });
      this.gradThreshold = gradThreshold.line;
      this.gradLabel = gradThreshold.label;

      // X axis
      this.xAxisG = renderXAxis(g, xScale, {
        tickCount: Math.min(data.length, 10),
        tickFormat: d3.format("d"),
        innerHeight,
        innerWidth,
        label: "CYCLE"
      });

      // Y axis
      this.yAxisG = renderYAxis(g, yScale, {
        tickCount: 5,
        tickFormat: d3.format(".0%"),
        innerHeight,
        label: "SUPPORT"
      });
    }

    // Line generator
    const line = d3
      .line()
      .x((d) => xScale(d.cycle))
      .y((d) => yScale(d.support))
      .curve(d3.curveLinear);

    // Sort data by cycle
    const sortedData = [...data].sort((a, b) => a.cycle - b.cycle);

    if (isUpdate && this.linePath) {
      // Animate line extension
      this.linePath.datum(sortedData).transition().duration(300).attr("d", line);
    } else {
      // Draw the line - white on dark
      this.linePath = g.append("path")
        .datum(sortedData)
        .attr("fill", "none")
        .attr("stroke", "#ffffff")
        .attr("stroke-width", 2)
        .attr("d", line);
    }

    // Update points - identify new points for fade-in
    const existingPoints = this.points ? this.points.data().map(d => d.cycle) : [];
    const newPoints = sortedData.filter(d => !existingPoints.includes(d.cycle));

    // Draw or update points
    const points = g.selectAll(".point")
      .data(sortedData, (d) => d.cycle);

    points.exit().remove();

    const pointsEnter = points.enter()
      .append("circle")
      .attr("class", "point")
      .attr("cx", (d) => xScale(d.cycle))
      .attr("cy", (d) => yScale(d.support))
      .attr("r", 4)
      .attr("fill", (d) => supportToColor(d.support))
      .attr("stroke", "#ffffff")
      .attr("stroke-width", 1);

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
        .attr("cx", (d) => xScale(d.cycle))
        .attr("cy", (d) => yScale(d.support));
    }

    // Mark current position (last point) with larger point
    if (sortedData.length > 0) {
      const lastPoint = sortedData[sortedData.length - 1];
      if (isUpdate && this.currentPointMarker) {
        this.currentPointMarker
          .transition()
          .duration(TRANSITION_DURATION)
          .attr("cx", xScale(lastPoint.cycle))
          .attr("cy", yScale(lastPoint.support));
      } else {
        this.currentPointMarker = g.append("circle")
          .attr("cx", xScale(lastPoint.cycle))
          .attr("cy", yScale(lastPoint.support))
          .attr("r", 7)
          .attr("fill", "none")
          .attr("stroke", "#ffffff")
          .attr("stroke-width", 2);
      }
    }

    // Add claim change markers
    this.renderClaimMarkers(g, claim_transitions, xScale, yScale, innerHeight, isUpdate);

    // Add tooltips with claim text
    this.renderTooltips(this.points, sortedData, xScale, yScale);

    // Store references for updates
    this.svg = svg;
    this.g = g;
    this.isInitialRender = false;
  },

  renderClaimMarkers(g, claim_transitions, xScale, yScale, innerHeight, isUpdate) {
    if (isUpdate && this.claimMarkersGroup) {
      this.claimMarkersGroup.remove();
    }

    if (!claim_transitions || claim_transitions.length === 0) {
      this.claimMarkersGroup = null;
      return;
    }

    this.claimMarkersGroup = g.append("g").attr("class", "claim-markers");

    claim_transitions.forEach((transition) => {
      const x = xScale(transition.to_cycle);
      
      // Vertical dashed line
      this.claimMarkersGroup.append("line")
        .attr("x1", x)
        .attr("x2", x)
        .attr("y1", 0)
        .attr("y2", innerHeight)
        .attr("stroke", "#a855f7")
        .attr("stroke-width", 1.5)
        .attr("stroke-dasharray", "4,4")
        .attr("opacity", 0.7);

      // Marker label
      const label = this.claimMarkersGroup.append("text")
        .attr("x", x + 5)
        .attr("y", 15)
        .attr("fill", "#a855f7")
        .attr("font-size", "9px")
        .attr("font-family", "monospace")
        .attr("text-anchor", "start")
        .text(`${transition.change_type || "Changed"}`);
      
      // Add trigger agent as second line
      if (transition.trigger_agent) {
        this.claimMarkersGroup.append("text")
          .attr("x", x + 5)
          .attr("y", 26)
          .attr("fill", "#a855f7")
          .attr("font-size", "8px")
          .attr("font-family", "monospace")
          .attr("text-anchor", "start")
          .attr("opacity", 0.7)
          .text(`by ${transition.trigger_agent.replace(/_/g, " ")}`);
      }
    });
  },

  renderTooltips(points, data, xScale, yScale) {
    const tooltipStyleOverrides = {
      background: "#1f2937",
      border: "1px solid #4b5563",
      "border-radius": "4px",
      "font-size": "11px",
      color: "#e5e7eb",
      "max-width": "300px",
      "box-shadow": "0 4px 6px rgba(0, 0, 0, 0.3)"
    };

    if (!points || this.tooltip) {
      if (this.tooltip) {
        this.tooltip.remove();
        this.tooltip = null;
      }
    }

    points.on("mouseover", (event, d) => {
      const claimText = d.claim_text || "No claim text available";

      if (!this.tooltip) {
        this.tooltip = createTooltip("support-timeline-tooltip", tooltipStyleOverrides);
      }

      const truncatedText = claimText.length > 150 ? claimText.substring(0, 150) + "..." : claimText;
      const html = `
        <div style="font-weight: bold; margin-bottom: 4px;">Cycle ${d.cycle}</div>
        <div style="margin-bottom: 4px;">Support: ${(d.support * 100).toFixed(1)}%</div>
        <div style="font-size: 10px; color: #9ca3af;">${truncatedText}</div>
      `;

      showTooltip(this.tooltip, html, event);
    })
    .on("mousemove", (event) => {
      if (this.tooltip) {
        this.tooltip
          .style("left", (event.pageX + 10) + "px")
          .style("top", (event.pageY - 10) + "px");
      }
    })
    .on("mouseout", () => {
      if (this.tooltip) {
        hideTooltip(this.tooltip);
      }
    });
  },
};

export { SupportTimelineHook };
