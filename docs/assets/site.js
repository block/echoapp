(() => {
  const root = document.documentElement;
  const themeButton = document.querySelector('.theme-button');
  const menuButton = document.querySelector('.menu-button');
  const sidebar = document.querySelector('.sidebar');
  const scrim = document.querySelector('.sidebar-scrim');
  const dialog = document.querySelector('.search-dialog');
  const searchInput = document.querySelector('#search-input');
  const results = document.querySelector('.search-results');
  const searchForm = document.querySelector('.search-box');
  const searchStatus = document.querySelector('.search-status');
  const themeColor = document.querySelector('meta[name="theme-color"]');
  let searchIndex;

  const preferredTheme = () => window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  const effectiveTheme = () => root.dataset.theme === 'auto' ? preferredTheme() : root.dataset.theme;
  const updateThemeLabel = () => {
    const theme = effectiveTheme();
    if (themeButton) themeButton.setAttribute('aria-label', `Use ${theme === 'dark' ? 'light' : 'dark'} theme`);
    themeColor?.setAttribute('content', theme === 'dark' ? '#0b1120' : '#ffffff');
  };

  themeButton?.addEventListener('click', () => {
    const next = effectiveTheme() === 'dark' ? 'light' : 'dark';
    root.dataset.theme = next;
    localStorage.setItem('echo-theme', next);
    updateThemeLabel();
  });
  updateThemeLabel();

  const setMenu = (open) => {
    sidebar?.classList.toggle('is-open', open);
    menuButton?.setAttribute('aria-expanded', String(open));
    if (scrim) scrim.hidden = !open;
    document.body.classList.toggle('menu-open', open);
  };
  menuButton?.addEventListener('click', () => setMenu(!sidebar?.classList.contains('is-open')));
  scrim?.addEventListener('click', () => setMenu(false));
  sidebar?.querySelectorAll('a').forEach((link) => link.addEventListener('click', () => setMenu(false)));

  const openSearch = async () => {
    dialog?.showModal();
    searchInput?.focus();
    if (!searchIndex) {
      try {
        const response = await fetch(document.body.dataset.searchUrl);
        searchIndex = await response.json();
        renderSearchResults();
      } catch (_) {
        results.innerHTML = '<p class="search-hint">Search could not be loaded. Try again after refreshing.</p>';
      }
    }
  };

  document.querySelector('.search-trigger')?.addEventListener('click', openSearch);
  document.addEventListener('keydown', (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
      event.preventDefault();
      openSearch();
    }
    if (event.key === 'Escape' && sidebar?.classList.contains('is-open')) setMenu(false);
  });

  const escapeHtml = (value) => value.replace(/[&<>'"]/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
  })[character]);

  const renderSearchResults = () => {
    if (!searchIndex) return;
    const query = searchInput.value.trim().toLowerCase();
    if (!query) {
      results.innerHTML = '<p class="search-hint">Start typing to search guides, concepts, and tools.</p>';
      searchStatus.textContent = '';
      return;
    }
    const terms = query.split(/\s+/);
    const matches = searchIndex
      .map((entry) => {
        const title = entry.title.toLowerCase();
        const haystack = `${title} ${entry.description} ${entry.content}`.toLowerCase();
        const matchesAll = terms.every((term) => haystack.includes(term));
        const score = terms.reduce((total, term) => total + (title.includes(term) ? 3 : 1), 0);
        return { entry, matchesAll, score };
      })
      .filter((item) => item.matchesAll)
      .sort((a, b) => b.score - a.score)
      .slice(0, 8);

    results.innerHTML = matches.length
      ? matches.map(({ entry }) => `<a class="search-result" href="${entry.url}"><strong>${escapeHtml(entry.title)}</strong><span>${escapeHtml(entry.description || '')}</span></a>`).join('')
      : `<p class="search-hint">No results for “${escapeHtml(searchInput.value)}”.</p>`;
    searchStatus.textContent = `${matches.length} ${matches.length === 1 ? 'result' : 'results'}`;
  };

  searchInput?.addEventListener('input', renderSearchResults);
  searchForm?.addEventListener('submit', (event) => {
    event.preventDefault();
    results?.querySelector('.search-result')?.click();
  });
  document.querySelector('.search-close')?.addEventListener('click', () => dialog?.close());

  document.querySelectorAll('.prose pre').forEach((pre) => {
    const copyText = pre.querySelector('code')?.innerText ?? pre.innerText;
    const button = document.createElement('button');
    button.className = 'copy-button';
    button.type = 'button';
    button.textContent = 'Copy';
    button.addEventListener('click', async () => {
      await navigator.clipboard.writeText(copyText);
      button.textContent = 'Copied';
      window.setTimeout(() => { button.textContent = 'Copy'; }, 1400);
    });
    pre.appendChild(button);
  });

  const toc = document.querySelector('#table-of-contents');
  const headings = [...document.querySelectorAll('.prose h2')];
  if (toc && headings.length) {
    headings.forEach((heading) => {
      const link = document.createElement('a');
      link.href = `#${heading.id}`;
      link.textContent = heading.textContent;
      toc.appendChild(link);
    });
  } else {
    document.querySelector('.on-this-page')?.remove();
  }
})();
