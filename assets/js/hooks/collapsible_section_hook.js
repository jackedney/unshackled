/**
 * CollapsibleSectionHook - Manages collapsible section state persistence
 *
 * This hook handles storing and restoring the expanded/collapsed state
 * of collapsible sections in sessionStorage. This ensures that state
 * persists across page refreshes within a tab session.
 *
 * If sessionStorage is unavailable (e.g., private browsing mode), the
 * section defaults to its initial expanded state.
 */

export const CollapsibleSectionHook = {
  mounted() {
    const el = this.el;
    const sectionId = el.id;
    const content = el.querySelector(`#${sectionId}-content`);
    const icon = el.querySelector(`#${sectionId}-icon`);
    const button = el.querySelector('button[aria-controls]');
    const dataExpanded = el.dataset.expanded === 'true';

    if (!content || !icon || !button) {
      console.warn(`CollapsibleSectionHook: Missing required elements for section ${sectionId}`);
      return;
    }

    try {
      const storageKey = `collapsible-${sectionId}`;
      const storedState = sessionStorage.getItem(storageKey);

      if (storedState !== null) {
        const isExpanded = storedState === 'expanded';
        this.updateSection(isExpanded, content, icon, button);
      } else {
        this.updateSection(dataExpanded, content, icon, button);
      }

      button.addEventListener('click', () => {
        const currentExpanded = button.getAttribute('aria-expanded') === 'true';
        const newExpanded = !currentExpanded;

        this.updateSection(newExpanded, content, icon, button);

        try {
          sessionStorage.setItem(storageKey, newExpanded ? 'expanded' : 'collapsed');
        } catch (error) {
          console.warn(`CollapsibleSectionHook: sessionStorage unavailable for section ${sectionId}`, error);
        }
      });
    } catch (error) {
      console.warn(`CollapsibleSectionHook: sessionStorage unavailable for section ${sectionId}`, error);
    }
  },

  updateSection(isExpanded, content, icon, button) {
    if (isExpanded) {
      content.style.display = 'block';
      icon.style.transform = 'rotate(90deg)';
      button.setAttribute('aria-expanded', 'true');
    } else {
      content.style.display = 'none';
      icon.style.transform = 'rotate(0deg)';
      button.setAttribute('aria-expanded', 'false');
    }
  }
};

