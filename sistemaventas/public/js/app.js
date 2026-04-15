document.addEventListener('DOMContentLoaded', () => {
  const menuToggle = document.querySelector('.menu-toggle');
  const mobileNav = document.querySelector('#main-nav');
  const sidebarToggle = document.querySelector('.sidebar-toggle');
  const body = document.body;

  if (menuToggle && mobileNav) {
    const setMobileOpen = (isOpen) => {
      mobileNav.classList.toggle('is-open', isOpen);
      menuToggle.classList.toggle('is-open', isOpen);
      menuToggle.setAttribute('aria-expanded', String(isOpen));
    };

    menuToggle.addEventListener('click', () => {
      setMobileOpen(!mobileNav.classList.contains('is-open'));
    });

    mobileNav.querySelectorAll('a').forEach((link) => {
      link.addEventListener('click', () => setMobileOpen(false));
    });

    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') {
        setMobileOpen(false);
      }
    });

    window.addEventListener('resize', () => {
      if (window.innerWidth > 900) {
        setMobileOpen(false);
      }
    });
  }

  if (sidebarToggle) {
    const storageKey = 'sidebar-collapsed';
    const applySidebarState = (collapsed) => {
      body.classList.toggle('sidebar-collapsed', collapsed);
      sidebarToggle.setAttribute('aria-expanded', String(!collapsed));
    };

    const savedState = window.localStorage.getItem(storageKey);
    applySidebarState(savedState === 'true');

    sidebarToggle.addEventListener('click', () => {
      const nextCollapsed = !body.classList.contains('sidebar-collapsed');
      applySidebarState(nextCollapsed);
      window.localStorage.setItem(storageKey, String(nextCollapsed));
    });
  }
});
