/**
 * CycleLogHook - Pulses the cycle log container when a new cycle is added
 *
 * This hook is attached to the cycle log container. When the
 * new_cycle_number data attribute is set, it adds a pulse animation
 * to draw attention to the update.
 */

export const CycleLogHook = {
  mounted() {
    this.checkForUpdate();
  },

  updated() {
    this.checkForUpdate();
  },

  checkForUpdate() {
    const newCycleNumber = this.el.dataset.newCycleNumber;

    if (newCycleNumber) {
      // Add pulse class to draw attention
      this.el.classList.add('cycle-log-pulse');

      // Remove pulse class after animation completes (1 second)
      setTimeout(() => {
        this.el.classList.remove('cycle-log-pulse');
      }, 1000);
    }
  }
};
