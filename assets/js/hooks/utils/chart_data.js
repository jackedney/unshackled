/**
 * Chart Data and Config Utilities
 * 
 * Shared utilities for parsing chart data attributes and extracting chart dimensions.
 * Used by all D3 and Plotly chart hooks to reduce code duplication.
 */

/**
 * Parse a JSON data attribute from an element's dataset.
 * 
 * @param {HTMLElement} el - The element containing the data attribute
 * @param {string} attrName - The dataset attribute name (without 'data-' prefix)
 * @param {any} fallback - Value to return if parsing fails or attribute is missing
 * @returns {any} Parsed data or fallback value
 */
export function parseChartData(el, attrName, fallback) {
  const dataAttr = el.dataset[attrName];

  if (!dataAttr) {
    console.warn(
      `Chart: Missing data-${attrName} attribute`,
      el.id
    );
    return fallback;
  }

  try {
    return JSON.parse(dataAttr);
  } catch (e) {
    console.warn(`Chart: Failed to parse data-${attrName}`, e);
    return fallback;
  }
}

/**
 * Get chart dimensions from an element's dataset.
 * 
 * Reads width, height, and margin attributes from the element's dataset
 * and computes inner dimensions. Falls back to defaults or clientWidth/Height.
 * 
 * @param {HTMLElement} el - The element containing dimension data attributes
 * @param {Object} defaults - Default dimension values
 * @param {number} defaults.width - Default width
 * @param {number} defaults.height - Default height
 * @param {Object} defaults.margin - Default margin values
 * @param {number} defaults.margin.top - Default top margin
 * @param {number} defaults.margin.right - Default right margin
 * @param {number} defaults.margin.bottom - Default bottom margin
 * @param {number} defaults.margin.left - Default left margin
 * @returns {Object} Chart dimensions with width, height, margin, and computed inner dimensions
 */
export function getChartDimensions(el, defaults) {
  const {
    width: defaultWidth,
    height: defaultHeight,
    margin: defaultMargin
  } = defaults;

  const width = parseInt(el.dataset.chartWidth) || el.clientWidth || defaultWidth;
  const height = parseInt(el.dataset.chartHeight) || defaultHeight;
  const margin = {
    top: parseInt(el.dataset.chartMarginTop) || defaultMargin.top,
    right: parseInt(el.dataset.chartMarginRight) || defaultMargin.right,
    bottom: parseInt(el.dataset.chartMarginBottom) || defaultMargin.bottom,
    left: parseInt(el.dataset.chartMarginLeft) || defaultMargin.left,
  };

  return {
    width,
    height,
    margin,
    innerWidth: width - margin.left - margin.right,
    innerHeight: height - margin.top - margin.bottom,
  };
}
