import { parseChartData, getChartDimensions } from './utils/chart_data.js';

/**
 * Trajectory3DPlotHook - Plotly.js 3D scatter plot for embedding space trajectory.
 *
 * Displays a 3D scatter plot showing the trajectory of claims through the embedding space:
 * - X/Y/Z from t-SNE-reduced embeddings
 * - Points connected with lines to show trajectory path
 * - Points colored by support strength (red -> yellow -> green)
 * - Point size by cycle number (larger = more recent)
 * - Diamond marker for current position
 * - X markers for cemetery claims, star markers for graduated claims
 *
 * Data format: {points: [{x, y, z, cycle, support, claim, status}, ...]}
 *
 * Dark brutalist aesthetic matching existing UI.
 */
const Trajectory3DPlotHook = {
  mounted() {
    this.renderPlot();
  },

  updated() {
    this.renderPlot();
  },

  destroyed() {
    if (this.el && typeof Plotly !== "undefined") {
      Plotly.purge(this.el);
    }
  },

  getData() {
    return parseChartData(this.el, 'chartData', { points: [] });
  },

  getConfig() {
    return getChartDimensions(this.el, {
      width: 600,
      height: 400,
      margin: { top: 0, right: 0, bottom: 0, left: 0 }
    });
  },

  supportToColor(support) {
    // Map support (0-1) to color gradient: red (low) -> yellow (mid) -> green (high)
    if (support <= 0.5) {
      // Red to yellow
      const t = support * 2;
      const r = 255;
      const g = Math.round(255 * t);
      const b = 0;
      return `rgb(${r},${g},${b})`;
    } else {
      // Yellow to green
      const t = (support - 0.5) * 2;
      const r = Math.round(255 * (1 - t));
      const g = 255;
      const b = 0;
      return `rgb(${r},${g},${b})`;
    }
  },

  cycleToSize(cycle, maxCycle) {
    // Map cycle to size: larger for more recent
    const minSize = 6;
    const maxSize = 16;
    if (maxCycle <= 1) return maxSize;
    const t = (cycle - 1) / (maxCycle - 1);
    return minSize + t * (maxSize - minSize);
  },

  renderPlot() {
    const data = this.getData();
    const config = this.getConfig();
    const points = data.points || [];

    // Empty state
    if (points.length === 0) {
      this.renderEmptyState(config);
      return;
    }

    // Sort points by cycle for line drawing
    const sortedPoints = [...points].sort((a, b) => a.cycle - b.cycle);
    const maxCycle = Math.max(...sortedPoints.map((p) => p.cycle));

    // Separate points by status
    const activePoints = sortedPoints.filter((p) => p.status === "active");
    const cemeteryPoints = sortedPoints.filter((p) => p.status === "cemetery");
    const graduatedPoints = sortedPoints.filter(
      (p) => p.status === "graduated"
    );
    const currentPoint = sortedPoints[sortedPoints.length - 1];

    // Build traces
    const traces = [];

    // Trajectory line trace
    if (sortedPoints.length > 1) {
      traces.push({
        type: "scatter3d",
        mode: "lines",
        x: sortedPoints.map((p) => p.x),
        y: sortedPoints.map((p) => p.y),
        z: sortedPoints.map((p) => p.z),
        line: {
          color: "#4b5563",
          width: 2,
        },
        hoverinfo: "skip",
        showlegend: false,
      });
    }

    // Active points trace
    if (activePoints.length > 0) {
      traces.push({
        type: "scatter3d",
        mode: "markers",
        name: "Active",
        x: activePoints.map((p) => p.x),
        y: activePoints.map((p) => p.y),
        z: activePoints.map((p) => p.z),
        text: activePoints.map(
          (p) =>
            `Cycle ${p.cycle}<br>Support: ${(p.support * 100).toFixed(1)}%<br>${p.claim ? p.claim.substring(0, 60) + (p.claim.length > 60 ? "..." : "") : ""}`
        ),
        hoverinfo: "text",
        marker: {
          size: activePoints.map((p) => this.cycleToSize(p.cycle, maxCycle)),
          color: activePoints.map((p) => this.supportToColor(p.support)),
          symbol: "circle",
          line: {
            color: "#ffffff",
            width: 1,
          },
        },
      });
    }

    // Cemetery points trace (X markers)
    if (cemeteryPoints.length > 0) {
      traces.push({
        type: "scatter3d",
        mode: "markers",
        name: "Cemetery",
        x: cemeteryPoints.map((p) => p.x),
        y: cemeteryPoints.map((p) => p.y),
        z: cemeteryPoints.map((p) => p.z),
        text: cemeteryPoints.map(
          (p) =>
            `DEAD - Cycle ${p.cycle}<br>Support: ${(p.support * 100).toFixed(1)}%<br>${p.claim ? p.claim.substring(0, 60) + (p.claim.length > 60 ? "..." : "") : ""}`
        ),
        hoverinfo: "text",
        marker: {
          size: 10,
          color: "#ef4444",
          symbol: "x",
          line: {
            color: "#ffffff",
            width: 1,
          },
        },
      });
    }

    // Graduated points trace (star markers)
    if (graduatedPoints.length > 0) {
      traces.push({
        type: "scatter3d",
        mode: "markers",
        name: "Graduated",
        x: graduatedPoints.map((p) => p.x),
        y: graduatedPoints.map((p) => p.y),
        z: graduatedPoints.map((p) => p.z),
        text: graduatedPoints.map(
          (p) =>
            `GRADUATED - Cycle ${p.cycle}<br>Support: ${(p.support * 100).toFixed(1)}%<br>${p.claim ? p.claim.substring(0, 60) + (p.claim.length > 60 ? "..." : "") : ""}`
        ),
        hoverinfo: "text",
        marker: {
          size: 12,
          color: "#22c55e",
          symbol: "diamond",
          line: {
            color: "#ffffff",
            width: 2,
          },
        },
      });
    }

    // Current position marker (diamond)
    if (currentPoint && currentPoint.status === "active") {
      traces.push({
        type: "scatter3d",
        mode: "markers",
        name: "Current",
        x: [currentPoint.x],
        y: [currentPoint.y],
        z: [currentPoint.z],
        text: [
          `CURRENT - Cycle ${currentPoint.cycle}<br>Support: ${(currentPoint.support * 100).toFixed(1)}%<br>${currentPoint.claim ? currentPoint.claim.substring(0, 60) + (currentPoint.claim.length > 60 ? "..." : "") : ""}`,
        ],
        hoverinfo: "text",
        marker: {
          size: 18,
          color: this.supportToColor(currentPoint.support),
          symbol: "diamond",
          line: {
            color: "#ffffff",
            width: 2,
          },
        },
      });
    }

    // Dark brutalist layout
    const layout = {
      width: config.width,
      height: config.height,
      paper_bgcolor: "#0a0a0a",
      plot_bgcolor: "#0a0a0a",
      margin: { l: 0, r: 0, t: 30, b: 0 },
      scene: {
        xaxis: {
          title: { text: "t-SNE 1", font: { color: "#6b7280", size: 10 } },
          gridcolor: "#333333",
          linecolor: "#333333",
          tickfont: { color: "#6b7280", size: 9 },
          backgroundcolor: "#0a0a0a",
          showbackground: true,
          zerolinecolor: "#4b5563",
        },
        yaxis: {
          title: { text: "t-SNE 2", font: { color: "#6b7280", size: 10 } },
          gridcolor: "#333333",
          linecolor: "#333333",
          tickfont: { color: "#6b7280", size: 9 },
          backgroundcolor: "#0a0a0a",
          showbackground: true,
          zerolinecolor: "#4b5563",
        },
        zaxis: {
          title: { text: "t-SNE 3", font: { color: "#6b7280", size: 10 } },
          gridcolor: "#333333",
          linecolor: "#333333",
          tickfont: { color: "#6b7280", size: 9 },
          backgroundcolor: "#0a0a0a",
          showbackground: true,
          zerolinecolor: "#4b5563",
        },
        camera: {
          eye: { x: 1.5, y: 1.5, z: 1.0 },
        },
        aspectmode: "cube",
      },
      legend: {
        x: 0,
        y: 1,
        font: { color: "#9ca3af", size: 10 },
        bgcolor: "rgba(0,0,0,0.5)",
        bordercolor: "#333333",
        borderwidth: 1,
      },
      hoverlabel: {
        bgcolor: "#1a1a1a",
        bordercolor: "#ffffff",
        font: { color: "#ffffff", family: "monospace", size: 11 },
      },
    };

    const plotConfig = {
      displayModeBar: true,
      modeBarButtonsToRemove: ["toImage", "sendDataToCloud"],
      displaylogo: false,
      responsive: true,
    };

    Plotly.react(this.el, traces, layout, plotConfig);
  },

  renderEmptyState(config) {
    const layout = {
      width: config.width,
      height: config.height,
      paper_bgcolor: "#0a0a0a",
      plot_bgcolor: "#0a0a0a",
      annotations: [
        {
          text: "No trajectory data yet",
          showarrow: false,
          font: { color: "#6b7280", size: 14, family: "monospace" },
          xref: "paper",
          yref: "paper",
          x: 0.5,
          y: 0.5,
        },
      ],
      xaxis: { visible: false },
      yaxis: { visible: false },
    };

    Plotly.react(this.el, [], layout, { displayModeBar: false });
  },
};

export { Trajectory3DPlotHook };
