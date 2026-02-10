export const CollapsibleSectionHook = {
  mounted() {
    const el = this.el;
    const { id: sectionId } = el;
    const content = el.querySelector(`#${sectionId}-content`);
    const icon = el.querySelector(`#${sectionId}-icon`);
    const button = el.querySelector('button[aria-controls]');

    if (!content || !icon || !button) {
      console.warn(`CollapsibleSectionHook: Missing required elements for section ${sectionId}`);
      return;
    }

    const storageKey = `collapsible-${sectionId}`;
    const update = (isExpanded) => {
      content.style.display = isExpanded ? 'block' : 'none';
      icon.style.transform = `rotate(${isExpanded ? 90 : 0}deg)`;
      button.setAttribute('aria-expanded', isExpanded);
    };

    try {
      const storedState = sessionStorage.getItem(storageKey);
      update(storedState !== null ? storedState === 'expanded' : el.dataset.expanded === 'true');

      button.addEventListener('click', () => {
        const newExpanded = button.getAttribute('aria-expanded') !== 'true';
        update(newExpanded);
        try { sessionStorage.setItem(storageKey, newExpanded ? 'expanded' : 'collapsed'); } catch (e) {}
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

