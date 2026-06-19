// AgentOS dashboard frontend. Polls the local control API and renders state.
const $ = (sel) => document.querySelector(sel);
const api = (p, opts) => fetch(p, opts).then((r) => {
  if (!r.ok) throw new Error(`${r.status}`);
  return r.json();
});

// Only these are user-controllable from the UI; mirrors backend allow-list.
const CONTROLS = {
  openclaw: ["start", "stop", "restart"],
  hermes: ["start", "stop", "restart"],
  ollama: ["restart"],
};

let currentLogUnit = null;

function toast(msg) {
  const t = $("#toast");
  t.textContent = msg;
  t.classList.add("show");
  clearTimeout(toast._t);
  toast._t = setTimeout(() => t.classList.remove("show"), 2600);
}

function fmtUptime(s) {
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
  return h ? `${h}h ${m}m` : `${m}m`;
}

function pill(active) {
  const cls = active === "active" ? "active" : active === "failed" ? "failed" : "inactive";
  const label = active === "active" ? "running" : active;
  return `<span class="pill ${cls}"><span class="dot"></span>${label}</span>`;
}

function renderAgents(services) {
  const wrap = $("#agent-cards");
  wrap.innerHTML = "";
  for (const [name, s] of Object.entries(services)) {
    if (name === "agentos-dashboard") continue; // don't let the UI kill itself
    const ctrls = CONTROLS[name] || [];
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `
      <div class="card-top">
        <span class="card-title">${s.label || name}</span>
        ${pill(s.active)}
      </div>
      <div class="muted small">${name}.service · ${s.enabled}</div>
      <div class="actions">
        ${ctrls.map((a) => `
          <button class="btn ${a === "start" || a === "restart" ? "primary" : ""}"
                  data-unit="${name}" data-action="${a}">${a}</button>`).join("")}
      </div>`;
    wrap.appendChild(card);
  }
  wrap.querySelectorAll("button[data-action]").forEach((b) => {
    b.addEventListener("click", () => control(b.dataset.unit, b.dataset.action, b));
  });
}

async function control(unit, action, btn) {
  btn.disabled = true;
  try {
    await api(`/api/agents/${unit}/${action}`, { method: "POST" });
    toast(`${unit}: ${action} ✓`);
    setTimeout(refresh, 600);
  } catch (e) {
    toast(`${unit}: ${action} failed (${e.message})`);
  } finally {
    btn.disabled = false;
  }
}

function renderSys(st) {
  $("#hostline").textContent = `${st.host} · ${st.os}`;
  $("#sysinfo").innerHTML = `
    <dt>Hostname</dt><dd>${st.host}</dd>
    <dt>Kernel</dt><dd>${st.kernel}</dd>
    <dt>Arch</dt><dd>${st.arch}</dd>
    <dt>Uptime</dt><dd>${fmtUptime(st.uptime_s)}</dd>`;
}

function renderLogSelect(services) {
  const sel = $("#log-select");
  if (sel.options.length) return; // build once
  for (const name of Object.keys(services)) {
    const o = document.createElement("option");
    o.value = name; o.textContent = name;
    sel.appendChild(o);
  }
  sel.addEventListener("change", () => loadLogs(sel.value));
  currentLogUnit = sel.value;
  loadLogs(currentLogUnit);
}

async function loadLogs(unit) {
  currentLogUnit = unit;
  try {
    const { log } = await api(`/api/logs/${unit}`);
    const view = $("#log-view");
    view.textContent = log || "(no log output)";
    view.scrollTop = view.scrollHeight;
  } catch {
    $("#log-view").textContent = "failed to load logs";
  }
}

async function renderModels() {
  try {
    const m = await api("/api/models");
    $("#ollama-state").textContent = m.reachable
      ? `${m.available.length} available · ${m.running.length} loaded`
      : "Ollama unreachable";
    const ul = $("#model-list");
    ul.innerHTML = m.available.length
      ? m.available.map((name) => `
          <li><span>${name}</span>${m.running.includes(name) ? '<span class="tag">loaded</span>' : ""}</li>`).join("")
      : '<li class="muted">no models pulled yet</li>';
  } catch {
    $("#ollama-state").textContent = "Ollama unreachable";
  }
}

async function refresh() {
  try {
    const st = await api("/api/status");
    renderSys(st);
    renderAgents(st.services);
    renderLogSelect(st.services);
  } catch { /* transient; next tick retries */ }
  renderModels();
  if (currentLogUnit) loadLogs(currentLogUnit);
}

function tickClock() {
  $("#clock").textContent = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

setInterval(tickClock, 1000);
setInterval(refresh, 5000);
tickClock();
refresh();
