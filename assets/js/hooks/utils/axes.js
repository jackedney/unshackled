import { applyTextStyle } from './chart_dom.js';

export function renderXAxis(g, xScale, config = {}) {
  const { tickCount = 5, tickFormat, innerHeight, innerWidth, label, labelOffset = 35 } = config;
  const xAxis = d3.axisBottom(xScale).ticks(tickCount);
  if (tickFormat) xAxis.tickFormat(tickFormat);
  const xAxisG = g.append("g").attr("transform", `translate(0,${innerHeight})`).call(xAxis).attr("color", "#9ca3af").selectAll("text").call(applyTextStyle);
  if (label) g.append("text").attr("x", innerWidth / 2).attr("y", innerHeight + labelOffset).attr("text-anchor", "middle").call(applyTextStyle, { fill: "#6b7280" }).text(label);
  return xAxisG;
}

export function renderYAxis(g, yScale, config = {}) {
  const { tickCount = 5, tickFormat, innerHeight, label, labelOffset = 40 } = config;
  const yAxis = d3.axisLeft(yScale).ticks(tickCount);
  if (tickFormat) yAxis.tickFormat(tickFormat);
  const yAxisG = g.append("g").call(yAxis).attr("color", "#9ca3af").selectAll("text").call(applyTextStyle);
  if (label) g.append("text").attr("transform", "rotate(-90)").attr("x", -innerHeight / 2).attr("y", -labelOffset).attr("text-anchor", "middle").call(applyTextStyle, { fill: "#6b7280" }).text(label);
  return yAxisG;
}

export function renderGridlines(g, scale, config = {}) {
  const { orientation = 'horizontal', tickCount = 5, values, innerWidth, innerHeight, color = '#333333', strokeWidth = 1 } = config;
  const ticks = values || scale.ticks(tickCount);
  const gridG = g.append("g").attr("class", `grid-${orientation}`);
  gridG.selectAll("line").data(ticks).enter().append("line")
    .attr("x1", orientation === 'horizontal' ? 0 : (d) => scale(d))
    .attr("x2", orientation === 'horizontal' ? innerWidth : (d) => scale(d))
    .attr("y1", orientation === 'horizontal' ? (d) => scale(d) : 0)
    .attr("y2", orientation === 'horizontal' ? (d) => scale(d) : innerHeight)
    .attr("stroke", color).attr("stroke-width", strokeWidth);
  return gridG;
}

export function renderThresholdLine(g, yScale, value, config = {}) {
  const { label, color = '#ef4444', strokeWidth = 2, dashArray = '5,5', innerWidth, textAlign = 'start', textDy = '0.35em' } = config;
  const line = g.append("line").attr("x1", 0).attr("x2", innerWidth).attr("y1", yScale(value)).attr("y2", yScale(value)).attr("stroke", color).attr("stroke-width", strokeWidth).attr("stroke-dasharray", dashArray);
  let labelText = null;
  if (label) {
    const xOffset = textAlign === 'start' ? 5 : -5;
    labelText = g.append("text").attr("x", innerWidth + xOffset).attr("y", yScale(value)).attr("dy", textDy).attr("text-anchor", textAlign === 'start' ? 'start' : 'end').call(applyTextStyle, { fill: color, "font-size": "10px" }).text(label);
  }
  return { line, label: labelText };
}
