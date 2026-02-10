import { FLASH_DISMISS_MS } from './utils/constants.js';

/**
 * FlashHook - Auto-dismisses info flash messages after 4 seconds
 *
 * This hook is attached to flash messages of kind=:info to automatically
 * dismiss them after a 4-second timeout. Error flash messages do not have
 * this hook and require manual dismissal.
 */

export const FlashHook = {
  mounted() {
    const el = this.el;

    setTimeout(() => {
      const closeButton = el.querySelector('button[aria-label="close"]');
      if (closeButton) {
        closeButton.click();
      }
    }, FLASH_DISMISS_MS);
  }
};
