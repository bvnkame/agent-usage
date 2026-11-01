// Numbers shown in the tray: remaining % of the 5-hour and weekly window per agent.
const AGENTS = [['claude', '#d97757'], ['codex', '#10a37f'], ['agy', '#6b8cff']];

const AGY_GROUPS = [['G', 'Gemini'], ['C', 'Claude/GPT'], ['A', 'Argon']];

function remaining(results, agent, window, group) {
  const limits = results.filter((r) => r.account.agent === agent && !r.errorKey && !r.errorRaw).flatMap((r) => r.limits).filter((l) => {
    if (group && !l.label.startsWith(group + ' ·')) return false;
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
    .map(([agent, color]) => {
      const d = { agent, color, h5: remaining(results, agent, '5h'), wk: remaining(results, agent, 'week') };
      // agy quota is per model group: extra small columns (G emini, C laude/GPT, A rgon)
      if (agent === 'agy') {
        d.cols = AGY_GROUPS.map(([tag, g]) => ({ tag, h5: remaining(results, agent, '5h', g), wk: remaining(results, agent, 'week', g) }))
          .filter((c) => c.h5 != null || c.wk != null);
      }
      return d;
    });
}

module.exports = { barData };
