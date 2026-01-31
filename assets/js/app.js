// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";

// Import LiveView hooks for D3 chart integrations
import Hooks from "./hooks";

// Debug: Log that JS is loading
console.log("[Unshackled] app.js loading...");

// Get CSRF token with error handling
let csrfToken;
try {
  const csrfMeta = document.querySelector("meta[name='csrf-token']");
  if (csrfMeta) {
    csrfToken = csrfMeta.getAttribute("content");
    console.log("[Unshackled] CSRF token found");
  } else {
    console.error("[Unshackled] CSRF meta tag not found!");
  }
} catch (e) {
  console.error("[Unshackled] Error getting CSRF token:", e);
}

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#ffffff" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
console.log("[Unshackled] Connecting LiveSocket...");
liveSocket.connect();
console.log("[Unshackled] LiveSocket.connect() called");

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// Debug: Check connection status after a delay
setTimeout(() => {
  if (liveSocket.isConnected()) {
    console.log("[Unshackled] LiveSocket connected successfully!");
  } else {
    console.warn("[Unshackled] LiveSocket not connected after 2s. Check WebSocket endpoint.");
  }
}, 2000);
