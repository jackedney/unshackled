import { applyTextStyle } from './chart_dom.js';

export function renderLegend(svg, items, config = {}) {
  if (!items || (Array.isArray(items) && items.length === 0)) return null;
  const { position = { x: 0, y: 0 }, type = 'grid', itemSize = { width: 100, height: 20 }, boxSize = { width: 12, height: 12 }, boxOffset = { x: 18, y: 10 }, spacing = { x: 0, y: 0 }, maxItemsPerRow = 3, labelStyle = {}, gradientSize = { width: 100, height: 10 }, stroke = '#ffffff', strokeWidth = 1 } = config;
  const legendGroup = svg.append('g').attr('class', 'legend-group').attr('transform', `translate(${position.x},${position.y})`);
  if (type === 'gradient') {
    renderGradientLegend(legendGroup, items, { gradientSize, stroke, strokeWidth, labelStyle });
  } else {
    renderGridLegend(legendGroup, items, { itemSize, boxSize, boxOffset, spacing, maxItemsPerRow, stroke, strokeWidth, labelStyle });
  }
  return legendGroup;
}

function renderGridLegend(legendGroup, items, config) {
  const { itemSize, boxSize, boxOffset, spacing, maxItemsPerRow, stroke, strokeWidth, labelStyle } = config;
  const legendItems = legendGroup.selectAll('.legend-item').data(items).enter().append('g').attr('class', 'legend-item').attr('transform', (d, i) => {
    const row = Math.floor(i / maxItemsPerRow);
    const col = i % maxItemsPerRow;
    return `translate(${col * itemSize.width},${row * itemSize.height})`;
  });
  legendItems.append('rect').attr('width', boxSize.width).attr('height', boxSize.height).attr('fill', (d) => d.color).attr('stroke', stroke).attr('stroke-width', strokeWidth);
  legendItems.append('text').attr('x', boxOffset.x).attr('y', boxOffset.y).call(applyTextStyle, { 'font-size': '10px', ...labelStyle });
}

function renderGradientLegend(legendGroup, items, config) {
  const { gradientSize, stroke, strokeWidth, labelStyle } = config;
  const defs = legendGroup.append('defs');
  const gradient = defs.append('linearGradient').attr('id', `gradient-${Date.now()}`).attr('x1', '0%').attr('x2', '100%');
  gradient.append('stop').attr('offset', '0%').attr('stop-color', items.startColor);
  gradient.append('stop').attr('offset', '100%').attr('stop-color', items.endColor);
  const gradientId = `url(#${gradient.attr('id')})`;
  legendGroup.append('rect').attr('width', gradientSize.width).attr('height', gradientSize.height).attr('fill', gradientId).attr('stroke', stroke).attr('stroke-width', strokeWidth);
  if (items.startLabel) legendGroup.append('text').attr('x', 0).attr('y', gradientSize.height + 12).call(applyTextStyle, { fill: '#6b7280', 'font-size': '10px', ...labelStyle }).text(items.startLabel);
  if (items.endLabel) legendGroup.append('text').attr('x', gradientSize.width).attr('y', gradientSize.height + 12).attr('text-anchor', 'end').call(applyTextStyle, { fill: '#6b7280', 'font-size': '10px', ...labelStyle }).text(items.endLabel);
  if (items.title) legendGroup.append('text').attr('x', gradientSize.width / 2).attr('y', -3).attr('text-anchor', 'middle').call(applyTextStyle, { 'font-size': '10px' }).text(items.title);
}
