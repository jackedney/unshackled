/**
 * CycleNewHook - Scrolls new cycle entries into view after update
 *
 * This hook is attached to cycle entries with the .cycle-new class.
 * It automatically scrolls the element into view and then removes the
 * animation class after it completes.
 */

export const CycleNewHook = {
  mounted() {
    const el = this.el;

    // Scroll the new cycle entry into view
    el.scrollIntoView({
      behavior: 'smooth',
      block: 'nearest',
      inline: 'nearest'
    });

    // Remove the animation class after it completes (1 second)
    setTimeout(() => {
      el.classList.remove('cycle-new');
    }, 1000);
  }
};
