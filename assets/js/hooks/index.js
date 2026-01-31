/**
 * LiveView Hooks for D3 chart integrations.
 *
 * Export all chart hooks from this file for easy registration
 * in the main app.js LiveSocket configuration.
 */
import { ChartHook } from "./chart_hook";
import { SupportTimelineHook } from "./support_timeline_hook";
import { ContributionsPieHook } from "./contributions_pie_hook";
import { TrajectoryPlotHook } from "./trajectory_plot_hook";
import { Trajectory3DPlotHook } from "./trajectory_3d_plot_hook";
import { FlashHook } from "./flash_hook";
import { InfiniteScrollHook } from "./infinite_scroll_hook";
import { CollapsibleSectionHook } from "./collapsible_section_hook";
import { CycleNewHook } from "./cycle_new_hook";
import { CycleLogHook } from "./cycle_log_hook";

const Hooks = {
  ChartHook,
  SupportTimelineHook,
  ContributionsPieHook,
  TrajectoryPlotHook,
  Trajectory3DPlotHook,
  FlashHook,
  InfiniteScrollHook,
  CollapsibleSectionHook,
  CycleNewHook,
  CycleLogHook
};

export default Hooks;
