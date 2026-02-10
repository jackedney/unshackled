export const CycleLogHook = {
  mounted() { this.checkForUpdate(); },
  updated() { this.checkForUpdate(); },

  checkForUpdate() {
    if (this.el.dataset.newCycleNumber) {
      this.el.classList.add('cycle-log-pulse');
      setTimeout(() => this.el.classList.remove('cycle-log-pulse'), 1000);
    }
  }
};
