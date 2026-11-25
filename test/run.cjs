// node test/run.cjs   (FLOW_SHELL=pwsh to use PowerShell 7 on Windows)
// Mock GitHub + GitLab; runs the real helper against them and checks the requests it sends.
const http = require('http'), fs = require('fs'), path = require('path'), { execFile, execFileSync } = require('child_process');
const os = require('os');
const REPO = path.resolve(__dirname, '..');
const ROOT = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'issue-flow-')), 'w').replace(/\\/g, '/');
const SHELL = process.env.FLOW_SHELL || (process.platform === 'win32' ? 'powershell' : 'pwsh');
const SH = ['-NoProfile', ...(process.platform === 'win32' ? ['-ExecutionPolicy', 'Bypass'] : []), '-File'];
const HOME_ENV = { ...process.env, USERPROFILE: process.platform === 'win32' ? path.resolve(ROOT + '/home') : '', HOME: path.resolve(ROOT + '/home') };
fs.rmSync(ROOT, { recursive: true, force: true }); fs.mkdirSync(ROOT + '/home/.config/issue-flow', { recursive: true });
const git = (...a) => execFileSync('git', a, { cwd: ROOT + '/r', stdio: 'pipe' }).toString();
execFileSync('git', ['init', '-q', '--bare', ROOT + '/o.git']); fs.mkdirSync(ROOT + '/r');
git('init', '-q', '-b', 'main'); git('config', 'user.email', 't@t'); git('config', 'user.name', 't');
fs.cpSync(REPO + '/.claude', ROOT + '/r/.claude', { recursive: true });
git('add', '-A'); git('commit', '-qm', 'i'); git('remote', 'add', 'origin', ROOT + '/o.git'); git('push', '-q', 'origin', 'main');
git('checkout', '-qb', '7-fix-login'); git('commit', '-q', '--allow-empty', '-m', 'w'); git('push', '-q', 'origin', 'HEAD');
let log = [], st = {};
const srv = http.createServer((q, r) => { let b = ''; q.on('data', (d) => b += d); q.on('end', () => {
  const u = q.url, m = q.method, body = b ? JSON.parse(b) : null; log.push([m, u, body, q.headers]);
  const out = (o, c = 200) => { r.writeHead(c, { 'content-type': 'application/json' }); r.end(o === undefined ? '' : JSON.stringify(o)); };
  const ok = q.headers.authorization === 'Bearer T' || q.headers['private-token'] === 'T'; if (!ok) return out({ message: 'no' }, 401);
  if (u.startsWith('/api/v3') || u === '/api/graphql') {
    const p = u.replace('/api/v3', ''), pr = { number: 12, title: 'Fix login', body: 'Closes #7', head: { ref: '7-fix-login' }, html_url: 'PRURL', draft: !!st.draft, node_id: 'NID', labels: [{ name: 'Status: In progress' }, { name: 'bug' }] };
    if (u === '/api/graphql') return out({ data: /reviewThreads/.test(body.query) ? { repository: { pullRequest: { reviewThreads: { pageInfo: { hasNextPage: false, endCursor: null }, nodes: [{ isResolved: false, path: 'a.java', line: 5, comments: { nodes: [{ author: { login: 'bob' }, body: 'fix ไทย' }] } }, { isResolved: true, path: 'b', line: 1, comments: { nodes: [] } }] } } } } : { x: 1 } });
    if (p === '/user') return out({ login: 'me', id: 1 }); if (p.startsWith('/users/ghost')) return out({}, 404); if (p.startsWith('/users/')) return out({ login: p.slice(7), id: 2 });
    if (p === '/repos/o/r') return out({ default_branch: 'main' }); if (p.startsWith('/repos/o/r/labels')) return out([{ name: 'Status: In progress' }]);
    if (p === '/repos/o/r/issues/7') return out({ number: 7, title: 'Fix login ไทย', state: 'open', labels: [{ name: 'Status: Awaiting review' }, { name: 'bug' }], assignees: [], user: { login: 'al' }, html_url: 'IURL', body: 'b', comments: 150 });
    if (p === '/repos/o/r/issues/8') return out({ number: 8, pull_request: {}, state: 'open' });
    if (p.startsWith('/repos/o/r/issues/7/comments')) return out([{ user: { login: 'c' }, created_at: '2026-01-01', body: 'last' }]);
    if (p.startsWith('/repos/o/r/pulls?')) return out(st.pr ? [pr] : []); if (p === '/repos/o/r/pulls' && m === 'POST') return out({ ...pr, number: 12 }, 201);
    if (p.includes('matching-refs')) return out([]); if (p === '/repos/o/r/git/ref/heads/main') return out({ object: { sha: 'SHA' } });
    if (p.endsWith('/requested_reviewers') && m === 'GET') return out({ users: [{ login: 'old' }] }); if (p.includes('/reviews')) return out([{ user: { login: 'z' }, state: 'CHANGES_REQUESTED', body: 'redo' }, { user: { login: 'y' }, state: 'CHANGES_REQUESTED', body: 'n' }, { user: { login: 'y' }, state: 'APPROVED', body: '' }]);
    if (m === 'DELETE' && p.includes('/labels/')) return out({}, 404); return out({}, 201);
  }
  const p = u.replace('/api/v4', ''), mr = { iid: 5, title: st.draft ? 'Draft: Fix' : 'Fix', description: 'Closes #7', source_branch: '7-fix-login', web_url: 'MRURL', draft: !!st.draft, labels: ['Status: In progress'] };
  if (p === '/user') return out({ username: 'me', id: 1 }); if (p.startsWith('/users?username=ghost')) return out([]); if (p.startsWith('/users?')) return out([{ username: 'bob', id: 2 }]);
  if (p === '/projects/g%2Fp') return out({ default_branch: 'main' }); if (p.includes('/labels?')) return out([]);
  if (p === '/projects/g%2Fp/issues/7' && m === 'GET') return out({ iid: 7, title: 'Fix login', state: 'opened', labels: ['Status: Awaiting review'], assignees: [], author: { username: 'a' }, web_url: 'IURL', description: 'd' });
  if (p.includes('/notes')) return out([{ author: { username: 'n2' }, body: 'new', created_at: '2' }, { author: { username: 'n1' }, body: 'old', created_at: '1' }]);
  if (p.includes('/merge_requests?')) return out(st.pr ? [mr] : []); if (p.includes('related_merge')) return out([]); if (p.includes('/branches?search')) return out([]);
  if (p.endsWith('/merge_requests') && m === 'POST') return out(mr, 201); if (p.includes('/discussions')) return out([{ notes: [{ author: { username: 'bob' }, body: 'x', resolvable: true, resolved: false, position: { new_path: 'a', new_line: 3 } }] }]); return out({});
}); });
let bad = 0; const chk = (n, c, x) => { if (!c) bad++; console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x))); };
// related-tests per stack
function stacks() {
  const D = ROOT + '/s'; const w = (f, t = '') => { fs.mkdirSync(path.dirname(D + '/' + f), { recursive: true }); fs.writeFileSync(D + '/' + f, t); };
  const g = (...x) => execFileSync('git', x, { cwd: D, stdio: 'pipe' }).toString();
  fs.mkdirSync(D); g('init', '-q', '-b', 'main'); g('config', 'user.email', 't@t'); g('config', 'user.name', 't');
  w('java/pom.xml'); w('java/src/main/java/Foo.java'); w('java/src/test/java/FooTest.java'); w('java/src/test/java/FooServiceIT.java'); w('java/src/test/java/BarTest.java');
  w('gr/build.gradle'); w('gr/src/main/kotlin/Baz.kt'); w('gr/src/test/kotlin/BazTest.kt');
  w('web/package.json', '{"devDependencies":{"vitest":"1"}}'); w('web/pnpm-lock.yaml'); w('web/src/cart.ts'); w('web/src/cart.test.ts'); w('web/src/other.test.ts');
  w('jest/package.json', '{"devDependencies":{"jest":"1"}}'); w('jest/a.js'); w('jest/a.spec.js');
  w('py/pyproject.toml'); w('py/app/pay.py'); w('py/tests/test_pay.py');
  w('go/go.mod'); w('go/pkg/x/x.go'); w('rs/Cargo.toml'); w('rs/src/lib.rs');
  w('net/App.csproj'); w('net/Order.cs'); w('net/OrderTests.cs'); w('php/composer.json'); w('php/src/User.php'); w('php/tests/UserTest.php');
  w('rb/Gemfile'); w('rb/lib/cat.rb'); w('rb/spec/cat_spec.rb'); w('bad/pyproject.toml'); w('bad/a b.py'); w('bad/test_a b.py'); w('docs/x.md');
  w('.claude/issue-flow.json', JSON.stringify({ host: 'https://gitlab.com' })); g('add', '-A'); g('commit', '-qm', 'i'); g('update-ref', 'refs/remotes/origin/main', 'HEAD');
  for (const f of ['java/src/main/java/Foo.java', 'gr/src/main/kotlin/Baz.kt', 'web/src/cart.ts', 'jest/a.js', 'py/app/pay.py', 'go/pkg/x/x.go', 'rs/src/lib.rs', 'net/Order.cs', 'php/src/User.php', 'rb/lib/cat.rb', 'bad/a b.py', 'docs/x.md']) fs.appendFileSync(D + '/' + f, '\n//x\n');
  const run = () => JSON.parse(execFileSync(SHELL, [...SH, REPO + '/.claude/scripts/issue-flow.ps1', 'related-tests'], { cwd: D, env: HOME_ENV }).toString());
  let r = run(); const by = Object.fromEntries(r.runs.map((x) => [x.dir, x]));
  const e = (d, re) => chk('related-tests: ' + d, by[d] && re.test(by[d].command), by[d]);
  e('java', /mvn test "-Dtest=FooServiceIT,FooTest" /); e('gr', /gradle test --tests "\*BazTest"/); e('web', /^pnpm exec vitest run src\/cart\.test\.ts$/); e('jest', /^npx jest a\.spec\.js$/);
  e('py', /^python -m pytest tests\/test_pay\.py$/); e('go', /^go test \.\/pkg\/x$/); e('net', /FullyQualifiedName~OrderTests"/); e('php', /--filter "UserTest"/); e('rb', /^bundle exec rspec spec\/cat_spec\.rb$/);
  chk('related-tests: rust falls back to all', by.rs && by.rs.command === '' && by.rs.all === 'cargo test', by.rs);
  chk('related-tests: unsafe file name never reaches a command', by.bad && by.bad.command === '' && by.bad.tests.length === 1, by.bad);
  chk('related-tests: no run for docs', !by.docs && !by['.'], by);
  w('.claude/issue-flow.json', JSON.stringify({ host: 'https://gitlab.com', tests: { related: 'make t', all: 'make all', issue: 'make i {issue}' } })); r = run();
  chk('related-tests: own commands win', r.runs.length === 1 && r.runs[0].command === 'make t' && r.runs[0].all === 'make all' && r.issue_command === 'make i {issue}', r);
  fs.rmSync(D + '/.claude', { recursive: true }); g('remote', 'add', 'origin', 'git@github.com:o/r.git');
  const init = () => JSON.parse(execFileSync(SHELL, [...SH, REPO + '/.claude/scripts/issue-flow.ps1', 'init'], { cwd: D, env: HOME_ENV }).toString());
  r = init(); chk('init (plugin layout) writes into the repository', r.created && r.provider === 'github' && fs.existsSync(D + '/.claude/issue-flow.json'), r); chk('init never overwrites', init().created === false);
}
srv.listen(0, '127.0.0.1', async () => {
  const port = srv.address().port, host = `127.0.0.1:${port}`;
  fs.writeFileSync(ROOT + `/home/.config/issue-flow/token-127.0.0.1_${port}.txt`, 'T\n');
  let provider;
  const run = (...a) => new Promise((res) => { log = []; fs.writeFileSync(ROOT + '/r/.claude/issue-flow.json', JSON.stringify({ provider, host: 'http://' + host, baseBranch: 'main', defaultReviewer: 'bob' }));
    execFile(SHELL, [...SH, ROOT + '/r/.claude/scripts/issue-flow.ps1', ...a, '--project', provider === 'github' ? 'o/r' : 'g/p'], { cwd: ROOT + '/r', env: HOME_ENV }, (e, so, se) => { let j; try { j = JSON.parse(so); } catch { j = so; } res({ code: e ? e.code : 0, j, se, w: log.filter((l) => l[0] !== 'GET').map((l) => `${l[0]} ${l[1]} ${JSON.stringify(l[2])}`), all: log }); }); });
  const has = (r, ...xs) => xs.every((x) => r.w.some((l) => l.includes(x)));
  for (provider of ['github', 'gitlab']) {
    const G = provider === 'github', t = (n) => provider + ': ' + n; st = {}; let r;
    r = await run('check'); chk(t('check'), r.code === 0 && r.j.token_user === 'me' && r.j.reviewers[0] === 'bob' && r.j.provider === provider, r);
    r = await run('issue', '7'); chk(t('issue + comments'), r.j.open === true && r.j.branch.startsWith('7-fix-login') && r.j.comments.at(-1).body === (G ? 'last' : 'new') && (!G || (r.j.title.endsWith('ไทย') && r.all.some((l) => l[1].includes('page=2')))), r);
    if (G) { r = await run('issue', '8'); chk(t('PR number refused'), r.code === 1 && /pull request/.test(r.se), r); }
    r = await run('find-change', '7'); chk(t('find none'), r.j === null || String(r.j).trim() === 'null', r);
    r = await run('start', '7'); chk(t('start'), r.code === 0 && (G ? has(r, 'POST /api/v3/repos/o/r/git/refs {"ref":"refs/heads/7-fix-login","sha":"SHA"}', '"labels":["Status: In progress"]', 'DELETE /api/v3/repos/o/r/issues/7/labels/Status%3A%20Awaiting%20review') && !has(r, '/pulls') && r.j.change === null : has(r, 'repository/branches?branch=7-fix-login&ref=main', '"title":"Draft: Fix login"', '"reviewer_ids":[2]', '"add_labels":"Status: In progress","remove_labels":"Status: Awaiting review"') && r.j.change === 'MRURL'), r);
    r = await run('start', '7', '--dry-run'); chk(t('dry-run writes nothing'), r.code === 0 && r.w.length === 0 && /dry-run/.test(r.j), r);
    r = await run('open-change', '7', '--draft'); chk(t('open draft'), r.code === 0 && r.j.created && (G ? has(r, '"head":"7-fix-login","base":"main","body":"Closes #7","draft":true', '"assignees":["me"]', 'requested_reviewers {"reviewers":["bob"]}') : has(r, '"title":"Draft: Fix login"')), r);
    st = { pr: 1, draft: 1 }; r = await run('open-change', '7'); chk(t('existing draft -> ready'), r.code === 0 && !r.j.created && !has(r, G ? 'POST /api/v3/repos/o/r/pulls {' : 'POST /api/v4/projects/g%2Fp/merge_requests') && (G ? has(r, 'markPullRequestReadyForReview') : has(r, '{"title":"Fix"}', '"add_labels":"Status: Awaiting review"')), r);
    st = { pr: 1 }; r = await run('reopen', '7'); chk(t('reopen -> draft'), r.code === 0 && (G ? has(r, 'convertPullRequestToDraft') : has(r, '{"title":"Draft: Fix"}')), r);
    r = await run('feedback', '7'); chk(t('feedback'), r.j.unresolved.length === (G ? 2 : 1) && r.j.unresolved[0].where === (G ? 'a.java:5' : 'a:3') && (!G || r.j.unresolved[0].text === 'bob: fix ไทย'), r);
    r = await run('set-reviewer', '7', '--reviewer', '@bob'); chk(t('set reviewer'), r.code === 0 && (G ? has(r, 'DELETE /api/v3/repos/o/r/pulls/12/requested_reviewers {"reviewers":["old"]}') : has(r, '{"reviewer_ids":[2]}')), r);
    if (G) { r = await run('open-change', '7', '--reviewer', 'me'); chk(t('author is not a reviewer'), r.code === 0 && !has(r, 'requested_reviewers'), r); }
    st = {}; r = await run('start', '7', '--reviewer', 'ghost'); chk(t('unknown reviewer: nothing written'), r.code === 1 && r.w.length === 0, r);
    r = await run('issue', 'https://evil.example.com/a/b/issues/7'); chk(t('other host refused'), r.code === 1 && r.all.length === 0, r);
    fs.renameSync(ROOT + `/home/.config/issue-flow/token-127.0.0.1_${port}.txt`, ROOT + '/t'); fs.writeFileSync(ROOT + '/home/.config/issue-flow/token-other.com.txt', 'T'); r = await run('issue', '7'); chk(t("another host's token never sent"), r.code === 1 && r.all.length === 0, r); fs.renameSync(ROOT + '/t', ROOT + `/home/.config/issue-flow/token-127.0.0.1_${port}.txt`);
    r = await run('issue'); chk(t('number required'), r.code === 1 && /number required/.test(r.se), r);
  }
  for (const c of ['fingerprint', 'related-tests', 'base-behind']) { const r = await run(c); chk(c, r.code === 0, r); }
  stacks(); console.log(bad ? bad + ' FAILED' : 'ALL PASS'); process.exitCode = bad ? 1 : 0; srv.close(); fs.rmSync(path.dirname(ROOT), { recursive: true, force: true });
});
