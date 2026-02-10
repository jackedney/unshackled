import { parseChartData, getChartDimensions } from './utils/chart_data.js';
import { cleanupSvg, createTooltip, showTooltip, hideTooltip } from './utils/chart_dom.js';
import { ROLE_COLORS, getRoleColor, formatRole, formatRoleShort } from './utils/colors.js';

/**
 * ContributionsPieHook - D3 pie/donut chart for agent contributions.
 *
 * Displays a pie chart showing contribution counts by agent role.
 * Each role has a distinct color and the chart includes a legend.
 *
 * Data format: [{role: 'explorer', count: 15, color: '#ff0000'}, ...]
 *
 * Brutalist aesthetic: sharp edges on segments, high contrast colors, no rounded caps.
 */
const ContributionsPieHook = {
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

    // Empty state
    if (filteredData.length === 0) {
      if (!isUpdate) {
        const svg = d3
          .select(this.el)
          .append("svg")
          .attr("width", width)
          .attr("height", height)
          .attr("class", "contributions-pie-svg");

        svg
          .append("text")
          .attr("x", width / 2)
          .attr("y", height / 2)
          .attr("text-anchor", "middle")
          .attr("fill", "#6b7280")
          .attr("font-family", "monospace")
          .text("No contributions yet");
      }
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

    // Create pie layout
    const pie = d3
      .pie()
      .value((d) => d.count)
      .sort(null); // Keep original order

    // Create arc generator - sharp edges (no corner radius)
    const arc = d3.arc().innerRadius(innerRadius).outerRadius(radius);

    // Arc for hover state
    const arcHover = d3
      .arc()
      .innerRadius(innerRadius)
      .outerRadius(radius + 8);

    // Create or get pie group
    let pieGroup;
    if (isUpdate && this.pieGroup) {
      pieGroup = this.pieGroup;
    } else {
      pieGroup = svg
        .append("g")
        .attr(
          "transform",
          `translate(${margin.left + pieWidth / 2},${margin.top + pieHeight / 2})`
        );
      this.pieGroup = pieGroup;
    }

    // Draw or update pie segments
    const pieData = pie(filteredData);
    const segments = pieGroup
      .selectAll(".segment")
      .data(pieData, (d) => d.data.role);

    segments.exit().remove();

    const segmentsEnter = segments.enter()
      .append("g")
      .attr("class", "segment");

      segmentsEnter
      .append("path")
      .attr("d", arc)
      .attr("fill", (d) => d.data.color || getRoleColor(d.data.role))
      .attr("stroke", "#0a0a0a")
      .attr("stroke-width", 2)
      .style("cursor", "pointer");

    if (isUpdate) {
      // Fade in new segments
      segmentsEnter.select("path")
        .attr("opacity", 0)
        .transition()
        .duration(300)
        .attr("opacity", 1);
    }

    const segmentsMerge = segmentsEnter.merge(segments);

    // Animate existing segments to new positions
    if (isUpdate) {
      segmentsMerge.select("path")
        .transition()
        .duration(300)
        .attr("d", arc)
        .attr("fill", (d) => d.data.color || getRoleColor(d.data.role));
    }

    // Create or update tooltip
    if (!this.tooltip) {
      this.tooltip = createTooltip("contributions-pie-tooltip");
    }
    const tooltip = this.tooltip;

    // Setup event handlers for segments
    segmentsMerge
      .on("mouseenter", function (event, d) {
        d3.select(this).select("path").transition().duration(100).attr("d", arcHover);

        showTooltip(
          tooltip,
          `<span class="font-bold">${formatRole(d.data.role)}</span><br>${d.data.count} contributions`,
          event
        );
      })
      .on("mouseleave", function () {
        d3.select(this).select("path").transition().duration(100).attr("d", arc);

        hideTooltip(tooltip);
      });

    // Draw or update center text (total count)
    const totalCount = filteredData.reduce((sum, d) => sum + d.count, 0);
    if (!isUpdate) {
      pieGroup
        .append("text")
        .attr("class", "center-label")
        .attr("text-anchor", "middle")
        .attr("dy", "-0.2em")
        .attr("fill", "#9ca3af")
        .attr("font-family", "monospace")
        .attr("font-size", "12px")
        .text("TOTAL");

      pieGroup
        .append("text")
        .attr("class", "center-count")
        .attr("text-anchor", "middle")
        .attr("dy", "1em")
        .attr("fill", "#ffffff")
        .attr("font-family", "monospace")
        .attr("font-size", "20px")
        .attr("font-weight", "bold")
        .text(totalCount);
    } else {
      pieGroup.select(".center-count")
        .text(totalCount);
    }

    // Draw legend below chart (only on initial render)
    if (!isUpdate) {
      const legendY = margin.top + pieHeight + 15;
      const legendGroup = svg
        .append("g")
        .attr(
          "transform",
          `translate(${margin.left},${legendY})`
        );

      // Calculate legend layout - center items below pie
      const itemsPerRow = 3;
      const itemWidth = 100;
      const itemHeight = 20;

      const legendItems = legendGroup
        .selectAll(".legend-item")
        .data(filteredData)
        .enter()
        .append("g")
        .attr("class", "legend-item")
        .attr("transform", (d, i) => {
          const row = Math.floor(i / itemsPerRow);
          const col = i % itemsPerRow;
          return `translate(${col * itemWidth},${row * itemHeight})`;
        });

      // Legend color boxes - sharp edges
      legendItems
        .append("rect")
        .attr("width", 12)
        .attr("height", 12)
        .attr("fill", (d) => d.color || getRoleColor(d.role))
        .attr("stroke", "#ffffff")
        .attr("stroke-width", 1);

      // Legend labels
      legendItems
        .append("text")
        .attr("x", 18)
        .attr("y", 10)
        .attr("fill", "#9ca3af")
        .attr("font-family", "monospace")
        .attr("font-size", "10px")
        .text((d) => `${formatRoleShort(d.role)} (${d.count})`);
    }

    // Store references for updates
    this.svg = svg;
    this.isInitialRender = false;
  },
};

export { ContributionsPieHook };
