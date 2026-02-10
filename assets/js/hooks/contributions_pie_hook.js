import { parseChartData, getChartDimensions } from './utils/chart_dom.js';
import { cleanupSvg, createTooltip, showTooltip, hideTooltip, applyTextStyle } from './utils/chart_dom.js';
import { ROLE_COLORS, getRoleColor, formatRole, formatRoleShort } from './utils/colors.js';
import { renderLegend } from './utils/legend.js';

const ContributionsPieHook = {
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
      width: 400,
      height: 300,
      margin: { top: 20, right: 120, bottom: 20, left: 20 }
    });
  },



  cleanup() {
    cleanupSvg(this.el);
  },

  renderChart() {
    const data = this.getData();
    const config = this.getConfig();
    const { width, height, margin } = config;
    const isUpdate = !this.isInitialRender;

    // Filter out roles with 0 contributions
    const filteredData = data.filter((d) => d.count > 0);

    if (filteredData.length === 0) {
      if (!isUpdate) d3.select(this.el).append("svg").attr("width", width).attr("height", height).attr("class", "contributions-pie-svg").append("text").attr("x", width / 2).attr("y", height / 2).attr("text-anchor", "middle").call(applyTextStyle, { fill: "#6b7280" }).text("No contributions yet");
      return;
    }

    let svg;
    if (isUpdate && this.svg) {
      svg = this.svg;
    } else {
      this.cleanup();
      svg = d3
        .select(this.el)
        .append("svg")
        .attr("width", width)
        .attr("height", height)
        .attr("class", "contributions-pie-svg");
    }

    // Calculate pie dimensions
    const pieWidth = width - margin.left - margin.right;
    const pieHeight = (height - margin.top - margin.bottom) * 0.7; // 70% height for pie, 30% for legend
    const radius = Math.min(pieWidth, pieHeight) / 2;
    const innerRadius = radius * 0.4; // Donut hole

    const pie = d3.pie().value(d => d.count).sort(null);
    const arc = d3.arc().innerRadius(innerRadius).outerRadius(radius);
    const arcHover = d3.arc().innerRadius(innerRadius).outerRadius(radius + 8);

    let pieGroup = isUpdate ? this.pieGroup : svg.append("g").attr("transform", `translate(${margin.left + pieWidth / 2},${margin.top + pieHeight / 2})`);
    if (!isUpdate) this.pieGroup = pieGroup;

    const pieData = pie(filteredData);
    const segments = pieGroup.selectAll(".segment").data(pieData, d => d.data.role);
    segments.exit().remove();

    const segmentsEnter = segments.enter().append("g").attr("class", "segment")
      .append("path")
      .attr("d", arc)
      .attr("fill", d => d.data.color || getRoleColor(d.data.role))
      .attr("stroke", "#0a0a0a")
      .attr("stroke-width", 2)
      .style("cursor", "pointer");

    if (isUpdate) {
      segmentsEnter.attr("opacity", 0).transition().duration(300).attr("opacity", 1);
    }

    const segmentsMerge = segmentsEnter.merge(segments);

    if (isUpdate) {
      segmentsMerge.transition().duration(300).attr("d", arc).attr("fill", d => d.data.color || getRoleColor(d.data.role));
    }

    if (!this.tooltip) this.tooltip = createTooltip("contributions-pie-tooltip");
    const tooltip = this.tooltip;

    segmentsMerge.on("mouseenter", function (event, d) {
      d3.select(this).select("path").transition().duration(100).attr("d", arcHover);
      showTooltip(tooltip, `<span class="font-bold">${formatRole(d.data.role)}</span><br>${d.data.count} contributions`, event);
    }).on("mouseleave", function () {
      d3.select(this).select("path").transition().duration(100).attr("d", arc);
      hideTooltip(tooltip);
    });

    const totalCount = filteredData.reduce((sum, d) => sum + d.count, 0);
    if (!isUpdate) {
      pieGroup.append("text").attr("class", "center-label").attr("text-anchor", "middle").attr("dy", "-0.2em").call(applyTextStyle).text("TOTAL");
      pieGroup.append("text").attr("class", "center-count").attr("text-anchor", "middle").attr("dy", "1em").call(applyTextStyle, { fill: "#ffffff", "font-size": "20px" }).attr("font-weight", "bold").text(totalCount);
    } else {
      pieGroup.select(".center-count").text(totalCount);
    }

    if (!isUpdate) {
      const legendY = margin.top + pieHeight + 15;
      renderLegend(svg, filteredData.map(d => ({ label: `${formatRoleShort(d.role)} (${d.count})`, color: d.color || getRoleColor(d.role) })), {
        position: { x: margin.left, y: legendY },
        type: 'grid',
        maxItemsPerRow: 3,
        labelStyle: { fill: '#9ca3af', 'font-family': 'monospace', 'font-size': '10px' },
      });
    }

    // Store references for updates
    this.svg = svg;
    this.isInitialRender = false;
  },
};

export { ContributionsPieHook };
