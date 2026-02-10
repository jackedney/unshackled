import { parseChartData, getChartDimensions } from './utils/chart_dom.js';
import { cleanupSvg, createTooltip, showTooltip, hideTooltip, applyTextStyle, escapeHtml } from './utils/chart_dom.js';
import { supportToColor, TRANSITION_DURATION, DEATH_THRESHOLD, GRADUATION_THRESHOLD } from './utils/colors.js';
import { renderXAxis, renderYAxis, renderGridlines, renderThresholdLine } from './utils/axes.js';

const SupportTimelineHook = {
  mounted() {
    this.isInitialRender = true;
    this.tooltip = null;
    this.renderChart();
  },
  updated() { this.renderChart(); },
  destroyed() { this.cleanup(); },

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

      if (this.xAxisG) {
        const xAxis = d3.axisBottom(newXScale).ticks(Math.min(data.length, 10)).tickFormat(d3.format("d"));
        this.xAxisG.transition().duration(TRANSITION_DURATION).call(xAxis).attr("color", "#9ca3af").selectAll("text").call(applyTextStyle);
      }
      if (this.yAxisG) {
        const yAxis = d3.axisLeft(newYScale).ticks(5).tickFormat(d3.format(".0%"));
        this.yAxisG.transition().duration(TRANSITION_DURATION).call(yAxis).attr("color", "#9ca3af").selectAll("text").call(applyTextStyle);
      }
      if (this.deathThreshold) {
        this.deathThreshold.transition().duration(TRANSITION_DURATION).attr("y1", newYScale(DEATH_THRESHOLD)).attr("y2", newYScale(DEATH_THRESHOLD));
        this.deathLabel?.transition().duration(TRANSITION_DURATION).attr("y", newYScale(DEATH_THRESHOLD));
      }
      if (this.gradThreshold) {
        this.gradThreshold.transition().duration(TRANSITION_DURATION).attr("y1", newYScale(GRADUATION_THRESHOLD)).attr("y2", newYScale(GRADUATION_THRESHOLD));
        this.gradLabel?.transition().duration(TRANSITION_DURATION).attr("y", newYScale(GRADUATION_THRESHOLD));
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
          .call(applyTextStyle, { fill: "#6b7280" })
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

    const line = d3.line().x(d => xScale(d.cycle)).y(d => yScale(d.support)).curve(d3.curveLinear);
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

    const existingPoints = this.points ? this.points.data().map(d => d.cycle) : [];
    const newPoints = sortedData.filter(d => !existingPoints.includes(d.cycle));

    const points = g.selectAll(".point").data(sortedData, d => d.cycle);
    points.exit().remove();

    const pointsEnter = points.enter()
      .append("circle")
      .attr("class", "point")
      .attr("cx", d => xScale(d.cycle))
      .attr("cy", d => yScale(d.support))
      .attr("r", 4)
      .attr("fill", d => supportToColor(d.support))
      .attr("stroke", "#ffffff")
      .attr("stroke-width", 1);

    if (isUpdate) {
      pointsEnter.attr("opacity", 0).transition().duration(TRANSITION_DURATION).attr("opacity", 1);
    }

    this.points = pointsEnter.merge(points);

    if (isUpdate) {
      this.points.transition().duration(TRANSITION_DURATION).attr("cx", d => xScale(d.cycle)).attr("cy", d => yScale(d.support));
    }

    if (sortedData.length) {
      const lastPoint = sortedData[sortedData.length - 1];
      if (isUpdate && this.currentPointMarker) {
        this.currentPointMarker.transition().duration(TRANSITION_DURATION).attr("cx", xScale(lastPoint.cycle)).attr("cy", yScale(lastPoint.support));
      } else {
        this.currentPointMarker = g.append("circle").attr("cx", xScale(lastPoint.cycle)).attr("cy", yScale(lastPoint.support)).attr("r", 7).attr("fill", "none").attr("stroke", "#ffffff").attr("stroke-width", 2);
      }
    }

    this.renderClaimMarkers(g, claim_transitions, xScale, innerHeight, isUpdate);
    this.renderTooltips(this.points);

    this.svg = svg;
    this.g = g;
    this.isInitialRender = false;
  },

  renderClaimMarkers(g, claim_transitions, xScale, innerHeight, isUpdate) {
    if (isUpdate) this.claimMarkersGroup?.remove();
    if (!claim_transitions?.length) { this.claimMarkersGroup = null; return; }

    this.claimMarkersGroup = g.append("g").attr("class", "claim-markers");
    claim_transitions.forEach((t) => {
      const x = xScale(t.to_cycle);
      this.claimMarkersGroup.append("line").attr("x1", x).attr("x2", x).attr("y1", 0).attr("y2", innerHeight).attr("stroke", "#a855f7").attr("stroke-width", 1.5).attr("stroke-dasharray", "4,4").attr("opacity", 0.7);
      this.claimMarkersGroup.append("text").attr("x", x + 5).attr("y", 15).attr("fill", "#a855f7").attr("font-size", "9px").attr("font-family", "monospace").attr("text-anchor", "start").text(`${t.change_type || "Changed"}`);
      if (t.trigger_agent) this.claimMarkersGroup.append("text").attr("x", x + 5).attr("y", 26).attr("fill", "#a855f7").attr("font-size", "8px").attr("font-family", "monospace").attr("text-anchor", "start").attr("opacity", 0.7).text(`by ${t.trigger_agent.replace(/_/g, " ")}`);
    });
  },

  renderTooltips(points) {
    const tooltipStyle = { background: "#1f2937", border: "1px solid #4b5563", "border-radius": "4px", "font-size": "11px", color: "#e5e7eb", "max-width": "300px", "box-shadow": "0 4px 6px rgba(0, 0, 0, 0.3)" };
    if (this.tooltip) { this.tooltip.remove(); this.tooltip = null; }
    if (!points) return;

    points.on("mouseover", (event, d) => {
      if (!this.tooltip) this.tooltip = createTooltip("support-timeline-tooltip", tooltipStyle);
      const claimText = d.claim_text || "No claim text available";
      const truncatedText = claimText.length > 150 ? claimText.substring(0, 150) + "..." : claimText;
      showTooltip(this.tooltip, `<div style="font-weight: bold; margin-bottom: 4px;">Cycle ${d.cycle}</div><div style="margin-bottom: 4px;">Support: ${(d.support * 100).toFixed(1)}%</div><div style="font-size: 10px; color: #9ca3af;">${escapeHtml(truncatedText)}</div>`, event);
    }).on("mousemove", (event) => {
      this.tooltip?.style("left", (event.pageX + 10) + "px").style("top", (event.pageY - 10) + "px");
    }).on("mouseout", () => {
      hideTooltip(this.tooltip);
    });
  },
};

export { SupportTimelineHook };
