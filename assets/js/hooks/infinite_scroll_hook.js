/**
 * InfiniteScrollHook - Detects scroll position to trigger loading more content.
 *
 * This hook monitors scroll events on its container element. When the user
 * scrolls near the bottom (within 200px), it triggers a "load_more" event
 * on the LiveView. Loading is debounced to prevent multiple rapid requests.
 *
 * Usage:
 *   <div id="infinite-scroll-container" phx-hook="InfiniteScrollHook">
 *     <!-- Content goes here -->
 *   </div>
 */

export const InfiniteScrollHook = {
  mounted() {
    this.el.addEventListener("scroll", this.handleScroll.bind(this));
    this.loaded = false;
    this.loading = false;
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting && !this.loading && !this.loaded) {
            this.loading = true;
            this.pushEvent("load_more", {});
          }
        });
      },
      {
        root: null,
        rootMargin: "200px",
        threshold: 0.1
      }
    );

    this.sentinel = document.createElement("div");
    this.sentinel.setAttribute("data-infinite-scroll-sentinel", "true");
    this.el.appendChild(this.sentinel);
    this.observer.observe(this.sentinel);
  },

  updated() {
    if (this.sentinel) {
      this.el.appendChild(this.sentinel);
      this.observer.observe(this.sentinel);
    }
  },

  destroyed() {
    this.observer?.disconnect();
  },

  reconnected() {
    this.loading = false;
    this.observer?.observe(this.sentinel);
  }
};
