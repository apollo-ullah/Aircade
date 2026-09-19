let mode = 'Arcade', sequence = 0;
async function refresh() {
  const request = ++sequence;
  try {
    const response = await fetch(`/api/leaderboard?difficulty=${mode}`);
    if (!response.ok) throw new Error();
    const data = await response.json();
    if (request !== sequence) return;
    document.querySelector('#scores').replaceChildren(...data.rows.map(row => {
      const tr = document.createElement('tr');
      for (const value of [row.rank, row.nickname, row.score.toLocaleString(), `${row.accuracy}%`, row.bestCombo]) {
        const td = document.createElement('td'); td.textContent = value; tr.append(td);
      }
      return tr;
    }));
    document.querySelector('#status').textContent = data.rows.length ? `${mode} · Updated ${new Date().toLocaleTimeString()}` : 'No public scores yet. Scan your badge and play the first round.';
  } catch { if (request === sequence) document.querySelector('#status').textContent = 'Leaderboard unavailable. Retrying shortly…'; }
}
document.querySelectorAll('button').forEach(button => button.addEventListener('click', () => {
  mode = button.dataset.mode;
  document.querySelectorAll('button').forEach(b => b.setAttribute('aria-pressed', b === button));
  refresh();
}));
refresh(); setInterval(refresh, 10000);
