// Loads the files of one character from the folder of its entry.json.

function lines(text, name) {
  const out = [];
  const rows = text.split('\n');
  for (let i = 0; i < rows.length; i++) {
    if (!rows[i].trim()) continue;
    try {
      out.push(JSON.parse(rows[i]));
    } catch {
      throw new Error(`${name}: line ${i + 1} is not valid JSON`);
    }
  }
  return out;
}

async function getOk(fetchFn, url, name) {
  const res = await fetchFn(url);
  if (!res.ok) throw new Error(`${name}: the server answered ${res.status}`);
  return res;
}

const getJson = async (fetchFn, url, name) => (await getOk(fetchFn, url, name)).json();
const getJsonl = async (fetchFn, url, name) => lines(await (await getOk(fetchFn, url, name)).text(), name);

export async function loadCharacter(entryUrl, fetchFn) {
  const base = new URL(entryUrl);
  const root = new URL('.', base).href;
  const entry = await getJson(fetchFn, base.href, 'entry.json');
  const own = (name, fallback) => {
    const url = new URL(typeof entry[name] === 'string' ? entry[name] : fallback, base);
    if (!url.href.startsWith(root)) throw new Error(`entry.json: ${name} points outside the character folder`);
    return url.href;
  };
  const [char, steps, trail] = await Promise.all([
    getJson(fetchFn, own('character', 'character.json'), 'character.json'),
    getJsonl(fetchFn, own('journey', 'journey.jsonl'), 'journey.jsonl'),
    getJsonl(fetchFn, own('trail', 'trail.jsonl'), 'trail.jsonl'),
  ]);
  const sorted = steps
    .map((s, i) => [s, i])
    .sort((a, b) => (a[0].t ?? 0) - (b[0].t ?? 0) || a[1] - b[1])
    .map((p) => p[0]);
  return { entry, char, steps: sorted, trail, root };
}

// The URL of a screenshot file that a record names, or null.
export function screenshotUrl(data, file) {
  if (typeof file !== 'string' || !/^[\w./-]+$/.test(file) || file.includes('..')) return null;
  const path = data.entry.path && data.entry.path !== '.' ? data.entry.path + '/' : '';
  return data.root + path + file;
}
