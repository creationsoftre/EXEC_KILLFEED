(function () {
  const resource = typeof GetParentResourceName === 'function'
    ? GetParentResourceName()
    : 'exec_killfeed';

  const shell = document.getElementById('killfeedShell');
  const list = document.getElementById('killfeedList');
  const dragOverlay = document.getElementById('dragOverlay');
  const dragHint = document.getElementById('dragHint');
  const dragSave = document.getElementById('dragSave');
  const dragCancel = document.getElementById('dragCancel');
  const placeholder = document.getElementById('killfeedPlaceholder');

  const state = {
    enabled: false,
    entries: [],
    anchor: { x: 0.985, y: 0.16 },
    config: {
      scale: 1,
      showDistance: false,
      showWeaponLabel: false,
      maxNameLength: 18,
    },
    drag: {
      enabled: false,
      active: false,
      anchor: null,
    },
  };

  function applyColors(colors) {
    if (!colors || typeof colors !== 'object') return;
    const map = {
      text: '--text',
      muted: '--muted',
      accent: '--accent',
      accentDark: '--accent-dark',
      killer: '--killer',
      victim: '--victim',
      surface: '--surface',
      surfaceAlt: '--surface-alt',
      stroke: '--stroke',
      placeholderBorder: '--placeholder-border',
      placeholderBg: '--placeholder-bg',
      entryFrom: '--entry-from',
      entryTo: '--entry-to',
      entryBorder: '--entry-border',
      dragBorder: '--drag-border',
      dragOverlayBg: '--drag-overlay-bg',
      dragCancelBorder: '--drag-cancel-border',
    };

    Object.entries(map).forEach(([key, cssVar]) => {
      const value = colors[key];
      if (value) {
        document.documentElement.style.setProperty(cssVar, value);
      }
    });
  }

  function updatePlaceholder() {
    if (!placeholder) return;
    const shouldShow = state.drag.enabled && state.entries.length === 0;
    placeholder.classList.toggle('hidden', !shouldShow);
  }

  function clamp(value, min, max) {
    return Math.min(Math.max(value, min), max);
  }

  function currentAnchor() {
    if (state.drag.enabled && state.drag.anchor) {
      return state.drag.anchor;
    }
    return state.anchor;
  }

  function applyAnchor(anchorOverride) {
    const src = anchorOverride || currentAnchor();
    shell.style.left = `${src.x * 100}vw`;
    shell.style.top = `${src.y * 100}vh`;
  }

  function viewportScaleFactor() {
    const widthFactor = window.innerWidth / 2560;
    const heightFactor = window.innerHeight / 1440;
    const responsive = Math.min(widthFactor, heightFactor);
    return Math.min(1, Math.max(0.82, responsive));
  }

  function applyScale() {
    const configured = Number(state.config.scale) || 1;
    const effective = configured * viewportScaleFactor();
    shell.style.transform = `translate(-100%, 0) scale(${effective.toFixed(3)})`;
  }

  function truncateName(value) {
    const raw = String(value || 'Unknown').trim() || 'Unknown';
    const limit = Math.max(8, Number(state.config.maxNameLength) || 18);
    if (raw.length <= limit) return raw;
    return `${raw.slice(0, limit - 3)}...`;
  }

  function setEnabled(flag) {
    state.enabled = Boolean(flag);
    shell.classList.toggle('hidden', !state.enabled);
  }

  function clearEntries() {
    state.entries.forEach((entry) => {
      if (entry.timer) {
        clearTimeout(entry.timer);
      }
    });
    state.entries = [];
    list.innerHTML = '';
    updatePlaceholder();
  }

  function removeEntry(id) {
    const idx = state.entries.findIndex((entry) => entry.id === id);
    if (idx === -1) return;
    const removed = state.entries.splice(idx, 1);
    const entry = removed[0];
    if (entry && entry.node) {
      entry.node.classList.add('fade');
      setTimeout(() => entry.node.remove(), 180);
    }
    if (entry.timer) {
      clearTimeout(entry.timer);
    }
    if (state.entries.length === 0) {
      updatePlaceholder();
    }
  }

  function safeValue(bucket, key, fallback) {
    if (bucket && Object.prototype.hasOwnProperty.call(bucket, key)) {
      const val = bucket[key];
      if (val !== undefined && val !== null && val !== '') {
        return val;
      }
    }
    return fallback;
  }

  function resolveIcon(payload) {
    if (payload.headshot) {
      return 'images/headshot.png';
    }
    return safeValue(payload.weapon, 'icon', 'images/unknown.png');
  }

  function resolveAssetUrl(path) {
    if (typeof path !== 'string' || path.trim() === '') {
      return `nui://${resource}/html/images/unknown.png`;
    }

    const trimmed = path.trim();
    if (/^(https?:|nui:|data:|blob:)/i.test(trimmed)) {
      return trimmed;
    }

    let localPath = trimmed.replace(/^\/+/, '');
    if (localPath.startsWith('html/')) {
      return `nui://${resource}/${localPath}`;
    }
    if (localPath.startsWith('images/')) {
      return `nui://${resource}/html/${localPath}`;
    }
    return `nui://${resource}/html/images/${localPath}`;
  }

  function setImageSource(img, path) {
    img.src = resolveAssetUrl(path);
    img.onerror = () => {
      img.onerror = null;
      img.src = resolveAssetUrl('images/unknown.png');
    };
  }

  function createEntry(payload) {
    const entry = document.createElement('div');
    entry.className = 'kill-entry';

    const killer = document.createElement('span');
    killer.className = 'player killer';
    killer.textContent = truncateName(payload.killer && payload.killer.name);

    const victim = document.createElement('span');
    victim.className = 'player victim';
    victim.textContent = truncateName(payload.victim && payload.victim.name);

    const weapon = document.createElement('div');
    weapon.className = 'weapon';
    const weaponImg = document.createElement('img');
    weaponImg.alt = safeValue(payload.weapon, 'label', 'Weapon');
    setImageSource(weaponImg, safeValue(payload.weapon, 'icon', 'images/unknown.png'));
    weapon.appendChild(weaponImg);

    if (state.config.showWeaponLabel) {
      const weaponLabel = document.createElement('span');
      weaponLabel.className = 'weapon-label';
      weaponLabel.textContent = safeValue(payload.weapon, 'label', 'Weapon');
      weapon.appendChild(weaponLabel);
    }

    if (state.config.showDistance && payload.distance) {
      const distance = document.createElement('span');
      distance.className = 'distance';
      distance.textContent = `${Math.round(Number(payload.distance) || 0)}m`;
      weapon.appendChild(distance);
    }

    const impact = document.createElement('div');
    impact.className = 'impact';
    if (payload.headshot) {
      const impactImg = document.createElement('img');
      impactImg.alt = 'Headshot';
      setImageSource(impactImg, resolveIcon(payload));
      impact.appendChild(impactImg);
    } else {
      const marker = document.createElement('span');
      marker.className = 'impact-marker';
      impact.appendChild(marker);
    }

    entry.appendChild(killer);
    entry.appendChild(weapon);
    entry.appendChild(impact);
    entry.appendChild(victim);

    return entry;
  }

  function addEntry(payload) {
    if (!payload || !state.enabled) return;

    const limit = payload.limit || 6;
    while (state.entries.length >= limit) {
      removeEntry(state.entries[state.entries.length - 1].id);
    }

    const node = createEntry(payload);
    list.insertBefore(node, list.firstChild);

    const duration = Math.max(2, Number(payload.duration) || 8);
    const timer = setTimeout(() => removeEntry(payload.id), duration * 1000);

    state.entries.unshift({ id: payload.id, node: node, timer: timer });
    updatePlaceholder();
  }

  function sendNuiCallback(name, data) {
    fetch(`https://${resource}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {}),
    });
  }

  function setDragMode(enabled, anchor) {
    state.drag.enabled = Boolean(enabled);
    state.drag.active = false;
    shell.style.pointerEvents = state.drag.enabled ? 'all' : 'none';
    dragOverlay.classList.toggle('hidden', !state.drag.enabled);
    if (anchor) {
      state.anchor = { x: anchor.x, y: anchor.y };
    }
    if (state.drag.enabled) {
      state.drag.anchor = { x: state.anchor.x, y: state.anchor.y };
    } else {
      state.drag.anchor = null;
    }
    applyAnchor();
    updatePlaceholder();
  }

  shell.addEventListener('pointerdown', (event) => {
    if (!state.drag.enabled) return;
    if (event.target && event.target.closest('.drag-btn')) {
      return;
    }
    state.drag.active = true;
    shell.setPointerCapture(event.pointerId);
    event.preventDefault();
  });

  shell.addEventListener('pointerup', (event) => {
    if (!state.drag.enabled || !state.drag.active) return;
    state.drag.active = false;
    shell.releasePointerCapture(event.pointerId);
  });

  shell.addEventListener('pointermove', (event) => {
    if (!state.drag.enabled || !state.drag.active) return;
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const anchor = {
      x: clamp(event.clientX / vw, 0.2, 0.995),
      y: clamp(event.clientY / vh, 0.04, 0.8),
    };
    state.drag.anchor = anchor;
    applyAnchor(anchor);
  });

  dragCancel.addEventListener('click', () => {
    if (state.drag.anchor) {
      state.drag.anchor = null;
      applyAnchor(state.anchor);
    }
    sendNuiCallback('killfeed:exitDrag');
  });

  dragSave.addEventListener('click', () => {
    if (!state.drag.enabled) return;
    const anchor = state.drag.anchor || state.anchor;
    sendNuiCallback('killfeed:savePosition', anchor);
  });

  let readyNotified = false;
  function notifyReady() {
    if (readyNotified) return;
    readyNotified = true;
    sendNuiCallback('killfeed:ready');
    updatePlaceholder();
  }
  window.addEventListener('DOMContentLoaded', notifyReady);
  window.addEventListener('load', notifyReady);
  setTimeout(notifyReady, 0);

  window.addEventListener('message', (event) => {
    const message = event.data || {};
    const payload = message.payload || {};
    switch (message.action) {
      case 'killfeed:config': {
        if (payload.anchor) {
          state.anchor = payload.anchor;
          applyAnchor();
        }
        const scale = (payload.scale === null || payload.scale === undefined) ? 1 : payload.scale;
        state.config.scale = scale;
        state.config.showDistance = payload.showDistance === true;
        state.config.showWeaponLabel = payload.showWeaponLabel === true;
        state.config.maxNameLength = Number(payload.maxNameLength) || state.config.maxNameLength;
        applyScale();
        if (payload.dragHint) {
          dragHint.textContent = payload.dragHint;
        }
        applyColors(payload.colors);
        break;
      }
      case 'killfeed:state':
        setEnabled(payload.enabled);
        break;
      case 'killfeed:push':
        addEntry(payload);
        break;
      case 'killfeed:clear':
        clearEntries();
        break;
      case 'killfeed:drag':
        setDragMode(payload.enabled, payload.anchor);
        break;
      default:
        break;
    }
  });

  ['resize', 'orientationchange'].forEach((eventName) => {
    window.addEventListener(eventName, applyScale);
  });
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', applyScale);
  }
})();
