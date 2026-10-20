// Numbers shown in the tray: remaining % of the 5-hour and weekly window per agent.
const AGENTS = [['claude', '#d97757'], ['codex', '#10a37f'], ['agy', '#6b8cff']];

// agy quota is per model group: only the group the default model draws from counts
function remaining(results, agent, window) {
  const limits = results.filter((r) => r.account.agent === agent && !r.errorKey && !r.errorRaw).flatMap((r) => {
    if (agent !== 'agy' || !r.defaultModel) return r.limits;
    const group = r.defaultModel.toLowerCase().includes('gemini') ? 'Gemini' : 'Claude/GPT';
    return r.limits.filter((l) => l.label.startsWith(group + ' ·'));
  }).filter((l) => {
    const t = l.label.toLowerCase();
    if (t.includes('credits') || t.includes('code review')) return false;
    const session = t.includes('5h') || t.includes('session');
    return window === '5h' ? session : (t.includes('week') || t.includes('secondary')) && !session;
  });
  if (!limits.length) return null;
  return Math.max(0, 100 - Math.max(...limits.map((l) => l.percent)));
}

function barData(results, show) {
  return AGENTS.filter(([a]) => (show === 'all' || show === a) && results.some((r) => r.account.agent === a))
    .map(([agent, color]) => ({ agent, color, h5: remaining(results, agent, '5h'), wk: remaining(results, agent, 'week') }));
}

module.exports = { barData };
