export function cleanupSvg(el) {
  d3.select(el).selectAll("svg").remove();
}

export function parseChartData(el, attrName, fallback) {
  const dataAttr = el.dataset[attrName];
  if (!dataAttr) { console.warn(`Chart: Missing data-${attrName} attribute`, el.id); return fallback; }
  try { return JSON.parse(dataAttr); } catch (e) { console.warn(`Chart: Failed to parse data-${attrName}`, e); return fallback; }
}

export function getChartDimensions(el, defaults) {
  const { width: defaultWidth, height: defaultHeight, margin: defaultMargin } = defaults;
  const getMargin = (side) => parseInt(el.dataset[`chartMargin${side.charAt(0).toUpperCase() + side.slice(1)}`]) || defaultMargin[side];
  const margin = { top: getMargin('top'), right: getMargin('right'), bottom: getMargin('bottom'), left: getMargin('left') };
  const width = parseInt(el.dataset.chartWidth) || el.clientWidth || defaultWidth;
  const height = parseInt(el.dataset.chartHeight) || defaultHeight;
  return { width, height, margin, innerWidth: width - margin.left - margin.right, innerHeight: height - margin.top - margin.bottom };
}

export function createTooltip(className, styleOverrides = {}) {
  const tooltip = d3.select("body").append("div").attr("class", className);
  Object.entries({ position: "absolute", padding: "8px 12px", background: "#1a1a1a", border: "2px solid #ffffff", color: "#ffffff", "font-family": "monospace", "font-size": "12px", "pointer-events": "none", opacity: 0, "z-index": 1000, ...styleOverrides })
    .forEach(([k, v]) => tooltip.style(k, v));
  return tooltip;
}

export function showTooltip(tooltip, html, event) {
  tooltip.style("opacity", 1).html(html).style("left", event.pageX + 10 + "px").style("top", event.pageY - 10 + "px");
}

export function hideTooltip(tooltip) {
  tooltip.style("opacity", 0);
}

export function removeTooltip(tooltip) {
  if (tooltip) tooltip.remove();
}

export function escapeHtml(str) {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#039;');
}

export function applyTextStyle(selection, overrides = {}) {
  return Object.entries({ fill: '#9ca3af', 'font-family': 'monospace', 'font-size': '12px', ...overrides })
    .reduce((sel, [k, v]) => sel.attr(k, v), selection);
}
