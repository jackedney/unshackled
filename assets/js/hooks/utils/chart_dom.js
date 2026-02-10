/**
 * chart_dom.js - DOM manipulation utilities for D3 charts
 *
 * Provides reusable functions for SVG cleanup and tooltip management.
 */

/**
 * Remove all SVG children from a DOM element
 * @param {HTMLElement} el - The container element
 */
export function cleanupSvg(el) {
  d3.select(el).selectAll("svg").remove();
}

/**
 * Create a tooltip div with standard styling
 * @param {string} className - CSS class name for the tooltip
 * @param {Object} styleOverrides - Optional style overrides
 * @returns {d3.Selection} D3 selection for the created tooltip
 */
export function createTooltip(className, styleOverrides = {}) {
  const defaultStyles = {
    position: "absolute",
    padding: "8px 12px",
    background: "#1a1a1a",
    border: "2px solid #ffffff",
    color: "#ffffff",
    "font-family": "monospace",
    "font-size": "12px",
    "pointer-events": "none",
    opacity: 0,
    "z-index": 1000
  };

  const styles = { ...defaultStyles, ...styleOverrides };

  return d3
    .select("body")
    .append("div")
    .attr("class", className)
    .styles(styles);
}

/**
 * Show a tooltip with HTML content positioned near an event
 * @param {d3.Selection} tooltip - D3 selection of the tooltip element
 * @param {string} html - HTML content to display
 * @param {Event} event - Mouse event for positioning
 */
export function showTooltip(tooltip, html, event) {
  tooltip
    .style("opacity", 1)
    .html(html)
    .style("left", (event.pageX + 10) + "px")
    .style("top", (event.pageY - 10) + "px");
}

/**
 * Hide a tooltip by setting opacity to 0
 * @param {d3.Selection} tooltip - D3 selection of the tooltip element
 */
export function hideTooltip(tooltip) {
  tooltip.style("opacity", 0);
}

/**
 * Remove a tooltip from the DOM
 * @param {d3.Selection} tooltip - D3 selection of the tooltip element
 */
export function removeTooltip(tooltip) {
  if (tooltip) {
    tooltip.remove();
  }
}
