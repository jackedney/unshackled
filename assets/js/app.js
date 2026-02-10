import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import Hooks from "./hooks";

console.log("[Unshackled] app.js loading...");

let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
console.log(csrfToken ? "[Unshackled] CSRF token found" : "[Unshackled] CSRF meta tag not found!");

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

topbar.config({ barColors: { 0: "#ffffff" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

console.log("[Unshackled] Connecting LiveSocket...");
liveSocket.connect();
console.log("[Unshackled] LiveSocket.connect() called");

window.liveSocket = liveSocket;

setTimeout(() => {
  if (liveSocket.isConnected()) {
    console.log("[Unshackled] LiveSocket connected successfully!");
  } else {
    console.warn("[Unshackled] LiveSocket not connected after 2s. Check WebSocket endpoint.");
  }
}, 2000);
