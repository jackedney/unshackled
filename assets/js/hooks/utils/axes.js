/**
 * Axes and Gridline Utilities
 * 
 * Provides reusable D3 axis and gridline rendering functions for consistent chart styling.
 */

/**
 * Render X axis with optional label.
 * @param {Object} g - D3 selection of the group to append axis to
 * @param {Function} xScale - D3 scale for the X axis
 * @param {Object} config - Configuration options
 * @param {number} config.tickCount - Number of ticks (default: 5)
 * @param {Function} config.tickFormat - D3 tick format function
 * @param {number} config.innerHeight - Inner height of the chart area for positioning
 * @param {number} config.innerWidth - Inner width of the chart area for label positioning
 * @param {string} config.label - Axis label text (optional)
 * @param {number} config.labelOffset - Offset for label from axis (default: 35)
 * @returns {Object} D3 selection of the axis group for updates
 */
export function renderXAxis(g, xScale, config = {}) {
  const {
    tickCount = 5,
    tickFormat = null,
    innerHeight,
    innerWidth,
    label = null,
    labelOffset = 35
  } = config;

  const xAxis = d3.axisBottom(xScale).ticks(tickCount);
  if (tickFormat) {
    xAxis.tickFormat(tickFormat);
  }

  const xAxisG = g.append("g")
    .attr("transform", `translate(0,${innerHeight})`)
    .call(xAxis)
    .attr("color", "#9ca3af")
    .selectAll("text")
    .attr("fill", "#9ca3af")
    .attr("font-family", "monospace");

  if (label) {
    g.append("text")
      .attr("x", innerWidth / 2)
      .attr("y", innerHeight + labelOffset)
      .attr("text-anchor", "middle")
      .attr("fill", "#6b7280")
      .attr("font-size", "12px")
      .attr("font-family", "monospace")
      .text(label);
  }

  return xAxisG;
}

/**
 * Render Y axis with optional label.
 * @param {Object} g - D3 selection of the group to append axis to
 * @param {Function} yScale - D3 scale for the Y axis
 * @param {Object} config - Configuration options
 * @param {number} config.tickCount - Number of ticks (default: 5)
 * @param {Function} config.tickFormat - D3 tick format function
 * @param {number} config.innerHeight - Inner height of the chart area for label positioning
 * @param {string} config.label - Axis label text (optional)
 * @param {number} config.labelOffset - Offset for label from axis (default: 40)
 * @returns {Object} D3 selection of the axis group for updates
 */
export function renderYAxis(g, yScale, config = {}) {
  const {
    tickCount = 5,
    tickFormat = null,
    innerHeight,
    label = null,
    labelOffset = 40
  } = config;

  const yAxis = d3.axisLeft(yScale).ticks(tickCount);
  if (tickFormat) {
    yAxis.tickFormat(tickFormat);
  }

  const yAxisG = g.append("g")
    .call(yAxis)
    .attr("color", "#9ca3af")
    .selectAll("text")
    .attr("fill", "#9ca3af")
    .attr("font-family", "monospace");

  if (label) {
    g.append("text")
      .attr("transform", "rotate(-90)")
      .attr("x", -innerHeight / 2)
      .attr("y", -labelOffset)
      .attr("text-anchor", "middle")
      .attr("fill", "#6b7280")
      .attr("font-size", "12px")
      .attr("font-family", "monospace")
      .text(label);
  }

  return yAxisG;
}

/**
 * Render dashed gridlines (horizontal or vertical).
 * @param {Object} g - D3 selection of the group to append gridlines to
 * @param {Function} scale - D3 scale to use for positioning
 * @param {Object} config - Configuration options
 * @param {string} config.orientation - 'horizontal' or 'vertical' (default: 'horizontal')
 * @param {number} config.tickCount - Number of gridlines (default: 5)
 * @param {Array} config.values - Array of values to draw gridlines at (overrides tickCount)
 * @param {number} config.innerWidth - Inner width for horizontal gridlines
 * @param {number} config.innerHeight - Inner height for vertical gridlines
 * @param {string} config.color - Gridline color (default: '#333333')
 * @param {number} config.strokeWidth - Gridline stroke width (default: 1)
 * @returns {Object} D3 selection of the gridline group for updates
 */
export function renderGridlines(g, scale, config = {}) {
  const {
    orientation = 'horizontal',
    tickCount = 5,
    values = null,
    innerWidth,
    innerHeight,
    color = '#333333',
    strokeWidth = 1
  } = config;

  const ticks = values || scale.ticks(tickCount);
  const gridG = g.append("g").attr("class", `grid-${orientation}`);

  gridG.selectAll("line")
    .data(ticks)
    .enter()
    .append("line")
    .attr("x1", orientation === 'horizontal' ? 0 : (d) => scale(d))
    .attr("x2", orientation === 'horizontal' ? innerWidth : (d) => scale(d))
    .attr("y1", orientation === 'horizontal' ? (d) => scale(d) : 0)
    .attr("y2", orientation === 'horizontal' ? (d) => scale(d) : innerHeight)
    .attr("stroke", color)
    .attr("stroke-width", strokeWidth);

  return gridG;
}

/**
 * Render a horizontal threshold/reference line with optional label.
 * @param {Object} g - D3 selection of the group to append line to
 * @param {Function} yScale - D3 scale for Y axis
 * @param {number} value - Y value where to draw the line
 * @param {Object} config - Configuration options
 * @param {string} config.label - Label text to display next to the line
 * @param {string} config.color - Line color (default: '#ef4444')
 * @param {number} config.strokeWidth - Line stroke width (default: 2)
 * @param {string} config.dashArray - Stroke dash array (default: '5,5')
 * @param {number} config.innerWidth - Inner width of the chart area
 * @param {string} config.textAlign - Label text alignment (default: 'start')
 * @param {string} config.textDy - Text dy attribute (default: '0.35em')
 * @returns {Object} Object with D3 selections for updates: {line, label}
 */
export function renderThresholdLine(g, yScale, value, config = {}) {
  const {
    label = null,
    color = '#ef4444',
    strokeWidth = 2,
    dashArray = '5,5',
    innerWidth,
    textAlign = 'start',
    textDy = '0.35em'
  } = config;

  const line = g.append("line")
    .attr("x1", 0)
    .attr("x2", innerWidth)
    .attr("y1", yScale(value))
    .attr("y2", yScale(value))
    .attr("stroke", color)
    .attr("stroke-width", strokeWidth)
    .attr("stroke-dasharray", dashArray);

  let labelText = null;
  if (label) {
    const xOffset = textAlign === 'start' ? 5 : -5;
    const textAnchor = textAlign === 'start' ? 'start' : 'end';
    
    labelText = g.append("text")
      .attr("x", innerWidth + xOffset)
      .attr("y", yScale(value))
      .attr("dy", textDy)
      .attr("text-anchor", textAnchor)
      .attr("fill", color)
      .attr("font-size", "10px")
      .attr("font-family", "monospace")
      .text(label);
  }

  return { line, label: labelText };
}
