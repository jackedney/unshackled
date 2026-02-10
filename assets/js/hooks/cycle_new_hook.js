export const CycleNewHook = {
  mounted() {
    this.el.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'nearest' });
    setTimeout(() => this.el.classList.remove('cycle-new'), 1000);
  }
};
