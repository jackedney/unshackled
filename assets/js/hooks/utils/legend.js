/**
 * Legend Rendering Utility
 *
 * Provides D3 legend rendering for charts with configurable layouts.
 * Supports both grid-based legends (color boxes) and gradient legends.
 *
 * Grid legend: Items with color boxes and labels in rows/columns
 * Gradient legend: Continuous gradient bar with labels
 */

/**
 * Render a legend on an SVG selection.
 *
 * @param {d3.Selection} svg - The SVG selection to append the legend to
 * @param {Array|Object} items - Legend data
 *   - For grid: Array of {label, color} objects
 *   - For gradient: Object with {startColor, endColor, startLabel, endLabel, title}
 * @param {Object} config - Legend configuration
 *   - position: {x, y} - Legend position (default: {x: 0, y: 0})
 *   - type: 'grid' | 'gradient' - Legend type (default: 'grid')
 *   - itemSize: {width, height} - Size of each item in grid legend (default: {width: 100, height: 20})
 *   - boxSize: {width, height} - Size of color box in grid legend (default: {width: 12, height: 12})
 *   - boxOffset: {x, y} - Offset of text from color box (default: {x: 18, y: 10})
 *   - spacing: {x, y} - Spacing between items in grid (default: {x: 0, y: 0})
 *   - maxItemsPerRow: number - Max items per row in grid (default: 3)
 *   - labelStyle: Object - Text style override (default: standard chart text style)
 *   - gradientSize: {width, height} - Size of gradient bar (default: {width: 100, height: 10})
 *   - stroke: string - Stroke color for boxes/gradient rect (default: '#ffffff')
 *   - strokeWidth: number - Stroke width (default: 1)
 * @returns {d3.Selection} The legend group selection
 */
export function renderLegend(svg, items, config = {}) {
  if (!items || (Array.isArray(items) && items.length === 0)) {
    return null;
  }

  const {
    position = { x: 0, y: 0 },
    type = 'grid',
    itemSize = { width: 100, height: 20 },
    boxSize = { width: 12, height: 12 },
    boxOffset = { x: 18, y: 10 },
    spacing = { x: 0, y: 0 },
    maxItemsPerRow = 3,
    labelStyle = {},
    gradientSize = { width: 100, height: 10 },
    stroke = '#ffffff',
    strokeWidth = 1,
  } = config;

  const legendGroup = svg
    .append('g')
    .attr('class', 'legend-group')
    .attr('transform', `translate(${position.x},${position.y})`);

  if (type === 'gradient') {
    renderGradientLegend(legendGroup, items, {
      gradientSize,
      stroke,
      strokeWidth,
      labelStyle,
    });
  } else {
    renderGridLegend(legendGroup, items, {
      itemSize,
      boxSize,
      boxOffset,
      spacing,
      maxItemsPerRow,
      stroke,
      strokeWidth,
      labelStyle,
    });
  }

  return legendGroup;
}

function renderGridLegend(legendGroup, items, config) {
  const {
    itemSize,
    boxSize,
    boxOffset,
    spacing,
    maxItemsPerRow,
    stroke,
    strokeWidth,
    labelStyle,
  } = config;

  const defaultLabelStyle = {
    fill: '#9ca3af',
    'font-family': 'monospace',
    'font-size': '10px',
  };
  const finalLabelStyle = { ...defaultLabelStyle, ...labelStyle };

  const legendItems = legendGroup
    .selectAll('.legend-item')
    .data(items)
    .enter()
    .append('g')
    .attr('class', 'legend-item')
    .attr('transform', (d, i) => {
      const row = Math.floor(i / maxItemsPerRow);
      const col = i % maxItemsPerRow;
      return `translate(${col * itemSize.width},${row * itemSize.height})`;
    });

  legendItems
    .append('rect')
    .attr('width', boxSize.width)
    .attr('height', boxSize.height)
    .attr('fill', (d) => d.color)
    .attr('stroke', stroke)
    .attr('stroke-width', strokeWidth);

  legendItems
    .append('text')
    .attr('x', boxOffset.x)
    .attr('y', boxOffset.y)
    .attr('fill', finalLabelStyle.fill)
    .attr('font-family', finalLabelStyle['font-family'])
    .attr('font-size', finalLabelStyle['font-size'])
    .text((d) => d.label);
}

function renderGradientLegend(legendGroup, items, config) {
  const {
    gradientSize,
    stroke,
    strokeWidth,
    labelStyle,
  } = config;

  const defaultLabelStyle = {
    fill: '#6b7280',
    'font-family': 'monospace',
    'font-size': '10px',
  };
  const finalLabelStyle = { ...defaultLabelStyle, ...labelStyle };

  const defs = legendGroup.append('defs');
  const gradient = defs
    .append('linearGradient')
    .attr('id', `gradient-${Date.now()}`)
    .attr('x1', '0%')
    .attr('x2', '100%');

  gradient.append('stop').attr('offset', '0%').attr('stop-color', items.startColor);
  gradient.append('stop').attr('offset', '100%').attr('stop-color', items.endColor);

  const gradientId = `url(#${gradient.attr('id')})`;

  legendGroup
    .append('rect')
    .attr('width', gradientSize.width)
    .attr('height', gradientSize.height)
    .attr('fill', gradientId)
    .attr('stroke', stroke)
    .attr('stroke-width', strokeWidth);

  if (items.startLabel) {
    legendGroup
      .append('text')
      .attr('x', 0)
      .attr('y', gradientSize.height + 12)
      .attr('fill', finalLabelStyle.fill)
      .attr('font-family', finalLabelStyle['font-family'])
      .attr('font-size', finalLabelStyle['font-size'])
      .text(items.startLabel);
  }

  if (items.endLabel) {
    legendGroup
      .append('text')
      .attr('x', gradientSize.width)
      .attr('y', gradientSize.height + 12)
      .attr('text-anchor', 'end')
      .attr('fill', finalLabelStyle.fill)
      .attr('font-family', finalLabelStyle['font-family'])
      .attr('font-size', finalLabelStyle['font-size'])
      .text(items.endLabel);
  }

  if (items.title) {
    legendGroup
      .append('text')
      .attr('x', gradientSize.width / 2)
      .attr('y', -3)
      .attr('text-anchor', 'middle')
      .attr('fill', '#9ca3af')
      .attr('font-family', 'monospace')
      .attr('font-size', '10px')
      .text(items.title);
  }
}
