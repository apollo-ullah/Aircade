const allowed = ['Arcade', 'Chill', 'Tennis'];
let mode = new URLSearchParams(location.search).get('mode') || 'Arcade', sequence = 0;
if (!allowed.includes(mode)) mode = 'Arcade';
const node = (tag, text, className) => { const el = document.createElement(tag); el.textContent = text; if (className) el.className = className; return el; };
function selected() {
  document.querySelectorAll('nav button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.mode === mode)));
}
async function refresh() {
  const request = ++sequence;
  try {
    const response = await fetch(`/api/leaderboard?difficulty=${encodeURIComponent(mode)}`, { signal: AbortSignal.timeout(8000) });
    if (!response.ok) throw new Error();
    const data = await response.json();
    if (request !== sequence) return;
    document.querySelector('#combo-heading').textContent = mode === 'Tennis' ? 'Longest rally' : 'Best combo';
    document.querySelector('#player-count').textContent = data.totalPlayers.toLocaleString();
    document.querySelector('#podium').replaceChildren(...data.rows.slice(0, 3).map(row => {
      const card = document.createElement('article'); card.className = `podium place-${row.rank}`;
      card.append(node('span', ['THE SCORE TO BEAT', 'NEXT IN LINE', 'ON THE PODIUM'][row.rank - 1], 'eyebrow'),
        node('div', `#${row.rank}`, 'place'), node('h2', row.nickname), node('strong', row.score.toLocaleString(), 'score'), node('span', 'POINTS', 'points'));
      return card;
    }));
    document.querySelector('#scores').replaceChildren(...data.rows.map(row => {
      const tr = document.createElement('tr');
      for (const value of [`#${row.rank}`, row.nickname, row.score.toLocaleString(), `${row.accuracy}%`, row.bestCombo]) tr.append(node('td', value));
      return tr;
    }));
    document.querySelector('#empty').hidden = data.rows.length > 0;
    document.querySelector('#status').textContent = `${mode === 'Tennis' ? 'Tennis' : `Neon Rush · ${mode}`} · Updated ${new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
  } catch {
    if (request === sequence) document.querySelector('#status').textContent = 'Connection interrupted. Retrying; previous scores may be out of date.';
  }
}
document.querySelectorAll('nav button').forEach(button => button.addEventListener('click', () => {
  if (mode === button.dataset.mode) return;
  mode = button.dataset.mode; selected();
  document.querySelector('#scores').replaceChildren(); document.querySelector('#podium').replaceChildren();
  document.querySelector('#empty').hidden = true; document.querySelector('#player-count').textContent = '—';
  document.querySelector('#status').textContent = 'Loading scores…';
  history.replaceState(null, '', `?mode=${mode}`); refresh();
}));
selected(); refresh(); setInterval(refresh, 10000);
