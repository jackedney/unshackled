export const TRANSITION_DURATION = 300;
export const FLASH_DISMISS_MS = 4000;
export const DEATH_THRESHOLD = 0.2;
export const GRADUATION_THRESHOLD = 0.85;

export const ROLE_COLORS = {
  explorer: "#22c55e", critic: "#ef4444", connector: "#3b82f6", steelman: "#eab308",
  operationalizer: "#f97316", quantifier: "#8b5cf6", reducer: "#06b6d4", boundary_hunter: "#ec4899",
  translator: "#14b8a6", historian: "#a855f7", grave_keeper: "#6b7280", cartographer: "#f59e0b", perturber: "#dc2626"
};

export function getRoleColor(role) {
  return ROLE_COLORS[role] || "#ffffff";
}

export function supportToColor(support) {
  if (support >= 0.85) return "#3b82f6";
  if (support >= 0.5) return "#22c55e";
  if (support >= 0.2) return "#eab308";
  return "#ef4444";
}

export function formatRole(role) {
  return role.split("_").map((word) => word.charAt(0).toUpperCase() + word.slice(1)).join(" ");
}

export function formatRoleShort(role, maxLen) {
  if (maxLen === undefined) {
    const abbrevs = { explorer: "EXP", critic: "CRT", connector: "CON", steelman: "STL", operationalizer: "OPR", quantifier: "QNT", reducer: "RED", boundary_hunter: "BND", translator: "TRN", historian: "HST", grave_keeper: "GRV", cartographer: "CRT", perturber: "PTB" };
    return abbrevs[role] || role.substring(0, 3).toUpperCase();
  }
  const formatted = formatRole(role);
  return formatted.length <= maxLen ? formatted : formatted.substring(0, maxLen - 1) + "…";
}

export function supportToColorGradient(support) {
  if (support <= 0.5) {
    const t = support * 2;
    return "#" + [255, Math.round(255 * t), 0].map(x => {
      const hex = x.toString(16);
      return hex.length === 1 ? "0" + hex : hex;
    }).join("");
  } else {
    const t = (support - 0.5) * 2;
    return "#" + [Math.round(255 * (1 - t)), 255, 0].map(x => {
      const hex = x.toString(16);
      return hex.length === 1 ? "0" + hex : hex;
    }).join("");
  }
}
