'use strict';

// Copy buttons on every code block.
document.querySelectorAll('.code').forEach((block) => {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'copy-btn';
  button.textContent = 'Copy';
  button.setAttribute('aria-label', 'Copy to clipboard');
  block.appendChild(button);
  button.addEventListener('click', async () => {
    const text = block.querySelector('code').innerText;
    try {
      await navigator.clipboard.writeText(text);
      button.textContent = 'Copied';
    } catch {
      const range = document.createRange();
      range.selectNodeContents(block.querySelector('code'));
      getSelection().removeAllRanges();
      getSelection().addRange(range);
      button.textContent = 'Selected';
    }
    clearTimeout(button.timer);
    button.timer = setTimeout(() => { button.textContent = 'Copy'; }, 1500);
  });
});

// Guide: off-canvas chapter list on small screens.
const menuButton = document.querySelector('.menu-btn');
const sidebar = document.getElementById('sidebar');
if (menuButton && sidebar) {
  const setOpen = (open) => {
    sidebar.classList.toggle('is-open', open);
    menuButton.setAttribute('aria-expanded', String(open));
  };
  menuButton.addEventListener('click', () => setOpen(!sidebar.classList.contains('is-open')));
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') setOpen(false); });
  sidebar.addEventListener('click', (e) => { if (e.target.closest('a')) setOpen(false); });
}

// Guide: highlight the section in view in "On this page".
const tocLinks = [...document.querySelectorAll('.doc-toc a')];
if (tocLinks.length && 'IntersectionObserver' in window) {
  const byId = new Map(tocLinks.map((a) => [decodeURIComponent(a.hash.slice(1)), a]));
  const headings = [...byId.keys()].map((id) => document.getElementById(id)).filter(Boolean);
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      tocLinks.forEach((a) => a.classList.remove('is-active'));
      byId.get(entry.target.id)?.classList.add('is-active');
    });
  }, { rootMargin: '0px 0px -70% 0px' });
  headings.forEach((h) => observer.observe(h));
}

// Guide: client-side search over the prebuilt index.
const input = document.getElementById('search-input');
const results = document.getElementById('search-results');
if (input && results && window.SEARCH_INDEX) {
  const esc = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const markTerms = (text, terms) => {
    let out = esc(text);
    for (const t of terms) out = out.replace(new RegExp(`(${t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})`, 'gi'), '<mark>$1</mark>');
    return out;
  };
  const snippet = (text, term) => {
    const i = text.toLowerCase().indexOf(term);
    if (i < 0) return text.slice(0, 120);
    const start = Math.max(0, i - 50);
    return (start ? '…' : '') + text.slice(start, start + 140) + '…';
  };

  function search(query) {
    const terms = query.toLowerCase().split(/\s+/).filter((t) => t.length > 1);
    if (!terms.length) return [];
    const hits = [];
    for (const page of window.SEARCH_INDEX) {
      const title = page.title.toLowerCase();
      const text = page.text.toLowerCase();
      if (!terms.every((t) => title.includes(t) || text.includes(t))) continue;
      let score = 0;
      for (const t of terms) {
        if (title.includes(t)) score += 10;
        score += Math.min(5, text.split(t).length - 1);
      }
      const heading = page.headings.find((h) => terms.some((t) => h.name.toLowerCase().includes(t)));
      if (heading) score += 4;
      hits.push({ page, heading, score, terms });
    }
    return hits.sort((a, b) => b.score - a.score).slice(0, 8);
  }

  function render() {
    const hits = search(input.value.trim());
    if (!input.value.trim()) { results.hidden = true; results.innerHTML = ''; return; }
    results.hidden = false;
    results.innerHTML = hits.length ? hits.map(({ page, heading, terms }, i) => {
      const href = page.url + (heading ? `#${heading.id}` : '');
      const label = heading ? `${page.title} › ${heading.name}` : page.title;
      return `<li><a href="${esc(href)}"${i === 0 ? ' aria-selected="true"' : ''}>${markTerms(label, terms)}<small>${markTerms(snippet(page.text, terms[0]), terms)}</small></a></li>`;
    }).join('') : '<li class="search__empty">No matches</li>';
  }

  let timer;
  input.addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(render, 80); });
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { const first = results.querySelector('a'); if (first) location.href = first.href; }
    if (e.key === 'Escape') { input.value = ''; render(); }
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === '/' && document.activeElement !== input && !/input|textarea/i.test(document.activeElement.tagName)) {
      e.preventDefault();
      input.focus();
    }
  });
}
