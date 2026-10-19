const $ = id => document.getElementById(id);
let state = {}, interacting = false, pending = null, sending = false, busy = false, initial = true;
const presets = [...document.querySelectorAll('.preset')];

async function api(path, data) {
  const res = await fetch(`/api/${path}`, data === undefined ? {} : {
    method: 'POST', headers: {'Content-Type': 'application/json', 'X-TV-Control': '1'}, body: JSON.stringify(data)
  });
  const result = await res.json();
  if (!res.ok) throw new Error(result.error || 'The TV did not respond.');
  return result;
}

function feedback(message, error = false) {
  $('feedback').textContent = message;
  $('feedback').classList.toggle('error', error);
}

function displayLevel(value) {
  $('level').textContent = value ?? '—';
  if (value !== null && value !== undefined) {
    $('brightness').value = value;
    $('brightness').style.setProperty('--position', `${value}%`);
    document.documentElement.style.setProperty('--glow', value / 100);
  }
  presets.forEach(button => {
    const selected = value === Number(button.dataset.value);
    button.classList.toggle('active', selected);
    button.setAttribute('aria-pressed', selected);
  });
}

function render(data) {
  state = data;
  const pairing = data.pairing || busy;
  $('status').className = `status ${pairing ? 'busy' : data.connected ? 'online' : ''}`;
  $('status').lastElementChild.textContent = pairing ? 'Connecting…' : data.connected ? 'Connected' : 'Not connected';
  $('brightness').disabled = !data.connected || pairing;
  presets.forEach(button => button.disabled = !data.connected || pairing);
  if (!interacting && pending === null && !sending) displayLevel(data.brightness);
  $('reading-caption').textContent = data.verified ? 'OLED pixel brightness · live from TV' : 'OLED pixel brightness';
  if (data.ip && !$('tv-ip').value) $('tv-ip').value = data.ip;
  if (!sending && pending === null && !interacting && !busy) {
    feedback(data.message || (data.connected ? 'Ready for your next movie night.' : 'Connect your TV to get started.'), !!data.message);
  }
  if (initial) {
    $('connection').hidden = !!data.connected;
    $('settings-toggle').setAttribute('aria-expanded', !data.connected);
    initial = false;
  }
}

async function refresh(live = false) {
  if (busy || sending || interacting || pending !== null || document.hidden) return;
  try { render(await api(`status${live ? '?refresh=1' : ''}`)); }
  catch { feedback('Cannot reach your Mac. Keep it awake and connected to this network.', true); }
}

async function sendLatest() {
  if (sending || pending === null) return;
  sending = true;
  const value = pending;
  pending = null;
  feedback('Adjusting the glow…');
  try {
    const result = await api('brightness', {brightness: value});
    state = result;
    if (pending === null && !interacting) {
      displayLevel(result.brightness);
      feedback(result.message || `Brightness set to ${result.brightness}%.`, !!result.message);
    }
  } catch (error) {
    pending = null;
    feedback(error.message, true);
    displayLevel(state.brightness);
  } finally {
    sending = false;
    if (pending === null && !interacting) $('reading-caption').textContent = state.verified ? 'OLED pixel brightness · live from TV' : 'OLED pixel brightness';
    if (pending !== null) sendLatest();
  }
}

let sliderTimer;
$('brightness').addEventListener('input', event => {
  interacting = true;
  displayLevel(Number(event.target.value));
  $('reading-caption').textContent = 'Release to set brightness';
});
$('brightness').addEventListener('change', event => {
  interacting = false;
  pending = Number(event.target.value);
  clearTimeout(sliderTimer);
  sliderTimer = setTimeout(sendLatest, 100);
});
presets.forEach(button => button.addEventListener('click', () => {
  const value = Number(button.dataset.value);
  displayLevel(value);
  pending = value;
  sendLatest();
}));

$('settings-toggle').addEventListener('click', () => {
  $('connection').hidden = !$('connection').hidden;
  $('settings-toggle').setAttribute('aria-expanded', !$('connection').hidden);
  if (!$('connection').hidden) $('connection').scrollIntoView({behavior: 'smooth', block: 'nearest'});
});

async function connect(ip) {
  if (busy) return;
  busy = true;
  render({...state, pairing: true});
  $('connect-button').disabled = true;
  $('discover').disabled = true;
  $('pairing-tip').textContent = 'Look at your TV now and choose Accept on the connection request.';
  feedback('Waiting for your TV. Choose Accept on its screen.');
  try {
    const data = await api('connect', {ip});
    busy = false;
    render(data);
    $('connection').hidden = true;
    $('settings-toggle').setAttribute('aria-expanded', 'false');
    $('pairing-tip').textContent = 'Your TV is paired. You can reconnect here at any time.';
  } catch (error) {
    busy = false;
    render({...state, connected: false, pairing: false});
    feedback(error.message, true);
    $('pairing-tip').textContent = error.message;
  } finally {
    busy = false;
    $('connect-button').disabled = false;
    $('discover').disabled = false;
  }
}

$('connect-form').addEventListener('submit', event => {
  event.preventDefault();
  connect($('tv-ip').value.trim());
});

$('discover').addEventListener('click', async () => {
  $('discover').disabled = true;
  $('discover').firstElementChild.textContent = 'Looking for your TV…';
  const results = $('discovery-results');
  results.replaceChildren();
  try {
    const data = await api('discover', {});
    if (data.tvs.length === 1) {
      $('tv-ip').value = data.tvs[0].ip;
      await connect(data.tvs[0].ip);
    } else if (data.tvs.length) {
      data.tvs.forEach(tv => {
        const button = document.createElement('button');
        button.className = 'found-tv';
        const label = document.createElement('span'); label.textContent = tv.name;
        const detail = document.createElement('small'); detail.textContent = `${tv.model} · ${tv.ip}`;
        button.append(label, detail);
        button.addEventListener('click', () => { $('tv-ip').value = tv.ip; connect(tv.ip); });
        results.append(button);
      });
    } else {
      const p = document.createElement('p');
      p.className = 'search-message';
      p.textContent = 'No TV found yet. Check that it’s switched on and connected to the same home network, or enter its IP address below.';
      results.append(p);
      $('manual').open = true;
    }
  } catch (error) { feedback(error.message, true); }
  finally {
    $('discover').disabled = false;
    $('discover').firstElementChild.textContent = 'Find my TV';
  }
});

refresh();
setInterval(() => refresh(true), 7000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(true); });
