export function cleanupSvg(el) {
  d3.select(el).selectAll("svg").remove();
}

export function parseChartData(el, attrName, fallback) {
  const dataAttr = el.dataset[attrName];
  if (!dataAttr) {
    console.warn(`Chart: Missing data-${attrName} attribute`, el.id);
    return fallback;
  }
  try {
    return JSON.parse(dataAttr);
  } catch (e) {
    console.warn(`Chart: Failed to parse data-${attrName}`, e);
    return fallback;
  }
}

export function getChartDimensions(el, defaults) {
  const { width: defaultWidth, height: defaultHeight, margin: defaultMargin } = defaults;
  const width = parseInt(el.dataset.chartWidth) || el.clientWidth || defaultWidth;
  const height = parseInt(el.dataset.chartHeight) || defaultHeight;
  const margin = {
    top: parseInt(el.dataset.chartMarginTop) || defaultMargin.top,
    right: parseInt(el.dataset.chartMarginRight) || defaultMargin.right,
    bottom: parseInt(el.dataset.chartMarginBottom) || defaultMargin.bottom,
    left: parseInt(el.dataset.chartMarginLeft) || defaultMargin.left,
  };
  return { width, height, margin, innerWidth: width - margin.left - margin.right, innerHeight: height - margin.top - margin.bottom };
}

export function createTooltip(className, styleOverrides = {}) {
  const defaultStyles = {
    position: "absolute", padding: "8px 12px", background: "#1a1a1a",
    border: "2px solid #ffffff", color: "#ffffff", "font-family": "monospace",
    "font-size": "12px", "pointer-events": "none", opacity: 0, "z-index": 1000
  };
  const styles = { ...defaultStyles, ...styleOverrides };
  const tooltip = d3.select("body").append("div").attr("class", className);
  for (const [key, value] of Object.entries(styles)) {
    tooltip.style(key, value);
  }
  return tooltip;
}

export function showTooltip(tooltip, html, event) {
  tooltip.style("opacity", 1).html(html).style("left", (event.pageX + 10) + "px").style("top", (event.pageY - 10) + "px");
}

export function hideTooltip(tooltip) {
  tooltip.style("opacity", 0);
}

export function removeTooltip(tooltip) {
  if (tooltip) tooltip.remove();
}

export function applyTextStyle(selection, overrides = {}) {
  const defaultStyle = { fill: '#9ca3af', 'font-family': 'monospace', 'font-size': '12px' };
  const style = { ...defaultStyle, ...overrides };
  for (const [key, value] of Object.entries(style)) {
    selection.attr(key, value);
  }
  return selection;
}
