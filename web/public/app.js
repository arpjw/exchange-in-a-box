/* The interface owns only display state. All market transitions run in OCaml. */
(() => {
  'use strict';
  const core = window.ExchangeBox;
  const $ = id => document.getElementById(id);
  const fmt = value => value == null ? '—' : Number(value).toLocaleString('en-US', { maximumFractionDigits: 4 });
  const parse = value => JSON.parse(value);
  const escape = value => String(value).replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
  const titles = {
    replay: ['MARKET REPLAY', 'Watch a market <em>take shape.</em>', 'Run a seeded OCaml simulation, inspect its state at every sampled step, and replay the exact same path.'],
    orders: ['ORDER SANDBOX', 'Meet the <em>matching engine.</em>', 'Place, match, cancel, and halt accounts against a live local book. Every action is checked by the OCaml risk core.'],
    router: ['VENUE ROUTER', 'Find the <em>cheapest path.</em>', 'Allocate displayed depth across three synthetic venues with fees and latency weights.'],
    intervention: ['INTERVENTION', 'Change one thing. <em>Compare both worlds.</em>', 'Use common random inputs to isolate a buy shock inside a declared synthetic population.']
  };

  if (!core) {
    document.body.innerHTML = '<main class="fatal"><h1>OCaml core unavailable</h1><p>Reload the page or check that bridge.bc.js was published.</p></main>';
    return;
  }

  function show(view) {
    const [crumb, title, subtitle] = titles[view];
    document.querySelectorAll('.view').forEach(el => el.classList.toggle('active', el.id === `view-${view}`));
    document.querySelectorAll('.nav-item').forEach(el => el.classList.toggle('active', el.dataset.view === view));
    $('crumb').textContent = crumb;
    $('view-title').innerHTML = title;
    $('view-subtitle').textContent = subtitle;
    if (location.hash !== `#${view}`) history.replaceState(null, '', `#${view}`);
  }
  document.querySelectorAll('.nav-item').forEach(button => button.addEventListener('click', () => show(button.dataset.view)));
  const initialView = location.hash.slice(1);
  if (Object.hasOwn(titles, initialView)) show(initialView);
  window.addEventListener('hashchange', () => {
    const view = location.hash.slice(1);
    if (Object.hasOwn(titles, view)) show(view);
  });

  function renderDepth(state, bidsId, asksId, spreadId, clickable = false) {
    const makeRows = (orders, side) => {
      if (!orders.length) return '<div class="depth-empty">NO RESTING ORDERS</div>';
      const visible = orders.slice(0, 8);
      const max = Math.max(...visible.map(order => order.quantity), 1);
      return visible.map(order => {
        const id = clickable ? `<button type="button" class="cancel-order" data-id="${order.id}" title="Cancel order ${order.id}">#${order.id}</button>` : `<span>#${order.id}</span>`;
        const price = `<span class="price">${fmt(order.price)}</span>`;
        const qty = `<span>${fmt(order.quantity)}</span>`;
        const inner = side === 'bid' ? `${qty}${price}` : `${price}${qty}`;
        return `<div class="depth-row ${side}" style="--width:${Math.max(8, order.quantity / max * 100)}%"><i class="bar"></i>${inner}</div>`;
      }).join('');
    };
    $(bidsId).innerHTML = makeRows(state.bids || [], 'bid');
    $(asksId).innerHTML = makeRows(state.asks || [], 'ask');
    $(spreadId).textContent = state.quote ? `SPREAD ${fmt(state.quote.spread)}` : 'SPREAD —';
    if (clickable) {
      // Separate cancel targets preserve owner authorization by using the order's ID.
      [...$(bidsId).querySelectorAll('.depth-row'), ...$(asksId).querySelectorAll('.depth-row')].forEach((row, index) => {
        const order = [...state.bids, ...state.asks][index];
        const button = document.createElement('button');
        button.type = 'button'; button.className = 'cancel-order'; button.textContent = `#${order.id} ×`;
        button.title = `Cancel order ${order.id}`;
        button.addEventListener('click', () => cancelOrder(order.id));
        row.prepend(button);
      });
    }
  }

  function drawChart(frames, selected) {
    const points = frames.map((frame, index) => ({ index, value: frame.quote ? (frame.quote.bid + frame.quote.ask) / 2 : null })).filter(p => p.value != null);
    if (points.length < 2) { $('scenario-chart').innerHTML = '<div class="chart-empty">INSUFFICIENT TWO-SIDED QUOTES FOR A PATH</div>'; return; }
    const width = 800, height = 250, left = 47, right = 18, top = 21, bottom = 35;
    const values = points.map(p => p.value), min = Math.min(...values), max = Math.max(...values);
    const lo = min === max ? min - 1 : min - (max - min) * .12;
    const hi = min === max ? max + 1 : max + (max - min) * .12;
    const x = index => left + index / Math.max(1, frames.length - 1) * (width - left - right);
    const y = value => top + (hi - value) / (hi - lo) * (height - top - bottom);
    const path = points.map((p, i) => `${i ? 'L' : 'M'} ${x(p.index).toFixed(1)} ${y(p.value).toFixed(1)}`).join(' ');
    const last = points.reduce((best, p) => Math.abs(p.index - selected) < Math.abs(best.index - selected) ? p : best, points[0]);
    const grid = [0, 1, 2, 3].map(i => { const gy = top + i * (height - top - bottom) / 3; const label = hi - i * (hi - lo) / 3; return `<line x1="${left}" y1="${gy}" x2="${width-right}" y2="${gy}" stroke="#2b3740" stroke-dasharray="3 5"/><text x="5" y="${gy+4}" fill="#72818b" font-size="11" font-family="monospace">${label.toFixed(1)}</text>`; }).join('');
    const marker = `<line x1="${x(last.index)}" y1="${top}" x2="${x(last.index)}" y2="${height-bottom}" stroke="#d5fb73" opacity=".45" stroke-dasharray="4 4"/><circle cx="${x(last.index)}" cy="${y(last.value)}" r="5" fill="#d5fb73" stroke="#111922" stroke-width="2"/>`;
    $('scenario-chart').innerHTML = `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Midpoint over ${frames.length} sampled states, selected value ${last.value}"><defs><linearGradient id="fill" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#d5fb73" stop-opacity=".21"/><stop offset="1" stop-color="#d5fb73" stop-opacity="0"/></linearGradient></defs>${grid}<path d="${path} L ${x(points.at(-1).index)} ${height-bottom} L ${x(points[0].index)} ${height-bottom} Z" fill="url(#fill)"/><path d="${path}" fill="none" stroke="#d5fb73" stroke-width="2" stroke-linejoin="round"/>${marker}<text x="${left}" y="${height-8}" fill="#72818b" font-size="10" font-family="monospace">INITIAL</text><text x="${width-right}" y="${height-8}" fill="#72818b" font-size="10" text-anchor="end" font-family="monospace">EVENT ${frames.at(-1).step}</text></svg>`;
  }

  let scenario = null;
  function selectFrame(index) {
    if (!scenario) return;
    const frames = scenario.frames, frame = frames[index];
    $('timeline').value = index;
    $('timeline-step').textContent = `EVENT ${fmt(frame.step)} / ${fmt(scenario.events)}`;
    renderDepth(frame, 'replay-bids', 'replay-asks', 'depth-spread');
    $('depth-imbalance').textContent = frame.quote ? `IMBALANCE ${frame.quote.imbalance.toFixed(3)}` : 'IMBALANCE —';
    drawChart(frames, index);
  }
  $('timeline').addEventListener('input', event => selectFrame(Number(event.target.value)));
  $('scenario-form').addEventListener('submit', event => {
    event.preventDefault();
    const button = event.submitter || event.currentTarget.querySelector('button[type="submit"]');
    const form = new FormData(event.currentTarget);
    button.disabled = true; button.firstChild.textContent = 'RUNNING… ';
    setTimeout(() => {
      try {
        const result = parse(core.scenario(Number(form.get('seed')), Number(form.get('events')), Number(form.get('agents')), Number(form.get('impact'))));
        if (result.error) throw Error(result.error);
        scenario = result; $('scenario-error').hidden = true;
        $('metric-mid').textContent = fmt(result.finalMid); $('metric-volume').textContent = fmt(result.volume);
        $('metric-fills').textContent = fmt(result.fills); $('metric-cost').textContent = fmt(result.impactCost);
        $('timeline').max = Math.max(0, result.frames.length - 1); selectFrame(result.frames.length - 1);
      } catch (error) { $('scenario-error').textContent = error.message; $('scenario-error').hidden = false; }
      finally { button.disabled = false; button.firstChild.textContent = 'RUN SCENARIO '; }
    }, 20);
  });

  const tape = [];
  let manual = parse(core.current());
  let manualHistory = [manual];
  function pushTape(message, good = true) {
    tape.unshift({ message, good }); tape.length = Math.min(tape.length, 15);
    $('event-tape').innerHTML = tape.map((item, i) => `<div class="tape-line ${item.good ? 'good':'bad'}"><span class="tape-index">${String(tape.length-i).padStart(2,'0')}</span><span class="tape-text">${escape(item.message)}</span></div>`).join('');
  }
  function renderManual(result) {
    manual = result; manualHistory.push(result);
    renderDepth(result, 'manual-bids', 'manual-asks', 'manual-spread', true);
    $('accounts-table').innerHTML = result.accounts.map(a => `<tr><td>#${a.id}</td><td>${fmt(a.position)}</td><td>${fmt(a.cash)}</td><td class="${a.halted ? 'status-halted' : 'status-active'}">${a.halted ? 'HALTED' : 'ACTIVE'}</td></tr>`).join('');
  }
  function ownerOf(id) {
    // The initial ladder belongs to accounts 0 and 1; UI orders use selected account.
    if (id < 1000) return id % 2 === 0 ? 0 : 1;
    return orderOwners.get(id);
  }
  const orderOwners = new Map();
  function cancelOrder(id) {
    const owner = ownerOf(id);
    if (owner == null) return;
    const result = parse(core.cancel(owner, id));
    renderManual(result); pushTape(`CANCEL #${id} · ${result.event}`, result.event === 'accepted');
  }
  for (let id = 0; id < 8; id++) {
    for (const select of [$('order-account'), $('risk-account')]) {
      const option = document.createElement('option'); option.value = id; option.textContent = `Account ${id}`; select.append(option);
    }
  }
  $('order-account').value = '2'; $('risk-account').value = '2';
  $('order-form').addEventListener('submit', event => {
    event.preventDefault();
    const data = new FormData(event.currentTarget), account = Number(data.get('account'));
    try {
      const result = parse(core.place(account, data.get('side'), Number(data.get('price')), Number(data.get('quantity')), data.get('policy')));
      if (result.event === 'accepted') orderOwners.set(result.orderId, account);
      renderManual(result);
      const good = result.event === 'accepted';
      $('order-notice').textContent = `ORDER #${result.orderId} · ${result.event.toUpperCase()} · ${result.trades.length} execution${result.trades.length === 1 ? '' : 's'}`;
      $('order-notice').classList.toggle('error-state', !good);
      pushTape(`PLACE #${result.orderId} ${data.get('side').toUpperCase()} ${data.get('quantity')} @ ${data.get('price')} · ${result.event}`, good);
    } catch (error) { $('order-notice').textContent = error.message; $('order-notice').classList.add('error-state'); }
  });
  $('reset-book').addEventListener('click', () => {
    orderOwners.clear(); tape.length = 0; manualHistory = [];
    renderManual(parse(core.reset())); pushTape('BOOK RESET · symmetric eight-level ladder');
    $('order-notice').textContent = 'The sandbox begins with a symmetric eight-level book.';
    $('order-notice').classList.remove('error-state');
  });
  for (const [id, method] of [['halt-account','halt'],['resume-account','resume']]) $(id).addEventListener('click', () => {
    const account = Number($('risk-account').value), result = parse(core[method](account));
    renderManual(result); pushTape(`${method.toUpperCase()} ACCOUNT ${account} · ${result.event}`, result.event === 'accepted');
  });

  $('router-form').addEventListener('submit', event => {
    event.preventDefault(); const d = new FormData(event.currentTarget);
    const result = parse(core.route(d.get('side'), Number(d.get('quantity')), Number(d.get('alpha')), Number(d.get('beta')), Number(d.get('gamma'))));
    if (result.error) { $('route-table').innerHTML = `<tr><td colspan="8">${escape(result.error)}</td></tr>`; return; }
    $('route-filled').textContent = `${fmt(result.filled)} / ${fmt(result.requested)}`;
    $('route-unfilled').textContent = fmt(result.unfilled);
    $('route-cost').textContent = fmt(result.totalCost);
    $('route-table').innerHTML = result.fills.map((fill, index) => `<tr><td>${String(index+1).padStart(2,'0')}</td><td>${escape(fill.venue)}</td><td>#${fill.maker}</td><td>${fmt(fill.price)}</td><td>${fmt(fill.quantity)}</td><td>${fmt(fill.fee)}</td><td>${fmt(fill.latency)}</td><td class="positive">${fmt(fill.unitCost)}</td></tr>`).join('');
  });

  $('intervention-form').addEventListener('submit', event => {
    event.preventDefault(); const d = new FormData(event.currentTarget);
    const button = event.submitter || event.currentTarget.querySelector('button[type="submit"]');
    button.disabled = true; button.firstChild.textContent = 'RUNNING… ';
    setTimeout(() => {
      try {
        const result = parse(core.intervention(Number(d.get('seed')), Number(d.get('events')), Number(d.get('shock')), d.get('regime')));
        if (result.error) throw Error(result.error);
        $('control-mid').textContent = fmt(result.controlMid);
        $('shock-mid').textContent = fmt(result.shockMid);
        $('pair-diff').textContent = result.difference == null ? '—' : `${result.difference >= 0 ? '+' : ''}${fmt(result.difference)}`;
        $('pair-filled').textContent = fmt(result.filledLots);
        $('pair-cost').textContent = fmt(result.shockCost);
        $('pair-digest').textContent = result.innovationDigest.slice(0, 10);
      } catch (error) { $('pair-diff').textContent = error.message; }
      finally { button.disabled = false; button.firstChild.textContent = 'RUN PAIR '; }
    }, 20);
  });

  renderManual(manual);
  pushTape('BOOK INITIALIZED · 16 resting orders');
  $('scenario-form').requestSubmit();
  $('router-form').requestSubmit();
  $('intervention-form').requestSubmit();
})();
