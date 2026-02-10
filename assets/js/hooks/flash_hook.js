import { FLASH_DISMISS_MS } from './utils/colors.js';

export const FlashHook = {
  mounted() {
    setTimeout(() => this.el.querySelector('button[aria-label="close"]')?.click(), FLASH_DISMISS_MS);
  }
};
