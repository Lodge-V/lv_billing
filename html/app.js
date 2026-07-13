(function () {
  const app = document.getElementById('app');

  let state = {
    invoices: { received: [], sent: [] },
    cityInvoices: [],
    players: [],
    context: null,
    selectedType: 'personal',
    items: [],       // { label, price } für "Neue Rechnung"
    groupSelected: new Set()
  };

  // ----------------------------------------------------
  // Helpers
  // ----------------------------------------------------

  function fmtMoney(amount) {
    return Number(amount).toLocaleString('de-DE') + '$';
  }

  function fmtDate(dateStr) {
    if (!dateStr) return '';
    const d = new Date(dateStr.replace(' ', 'T'));
    if (isNaN(d.getTime())) return dateStr;
    return d.toLocaleDateString('de-DE', { day: '2-digit', month: '2-digit', year: 'numeric' }) +
           ' · ' + d.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
  }

  function GetParentResourceName() {
    return window.GetParentResourceName ? window.GetParentResourceName() : 'esx_rechnungen';
  }

  async function callNui(name, data) {
    try {
      const resp = await fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {})
      });
      return await resp.json();
    } catch (e) {
      console.warn('NUI callback fehlgeschlagen (evtl. kein FiveM-Kontext):', name, e);
      return null;
    }
  }

  // ----------------------------------------------------
  // View-Navigation
  // ----------------------------------------------------

  document.querySelectorAll('.nav-btn[data-view]').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.nav-btn[data-view]').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
      btn.classList.add('active');
      document.getElementById(`view-${btn.dataset.view}`).classList.add('active');

      if (btn.dataset.view === 'city') loadCityInvoices();
      if (btn.dataset.view === 'team') loadLeaderboard();
      if (btn.dataset.view === 'group') renderGroupPlayerList();
    });
  });

  document.getElementById('closeBtn').addEventListener('click', () => {
    callNui('close');
    app.classList.add('hidden');
  });

  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !app.classList.contains('hidden')) {
      callNui('close');
      app.classList.add('hidden');
    }
  });

  // ----------------------------------------------------
  // Filter / Suche / Sortierung
  // ----------------------------------------------------

  function getFilterValues(scope) {
    const bar = document.querySelector(`.filter-bar[data-scope="${scope}"]`);
    if (!bar) return { search: '', status: 'all', sort: 'date_desc' };
    return {
      search: bar.querySelector('.filter-search').value.trim().toLowerCase(),
      status: bar.querySelector('.filter-status').value,
      sort: bar.querySelector('.filter-sort').value
    };
  }

  function applyFilters(list, filters, mode) {
    let result = (list || []).slice();

    if (filters.status !== 'all') {
      result = result.filter(i => i.status === filters.status);
    }

    if (filters.search) {
      result = result.filter(i => {
        const haystack = [
          i.item, i.ref_id,
          mode === 'sent' ? i.receiver_name : (i.author_name || i.society_label),
          i.society_label, i.notes
        ].filter(Boolean).join(' ').toLowerCase();
        return haystack.includes(filters.search);
      });
    }

    result.sort((a, b) => {
      switch (filters.sort) {
        case 'date_asc': return new Date(a.sent_date) - new Date(b.sent_date);
        case 'amount_desc': return Number(b.invoice_value) - Number(a.invoice_value);
        case 'amount_asc': return Number(a.invoice_value) - Number(b.invoice_value);
        default: return new Date(b.sent_date) - new Date(a.sent_date); // date_desc
      }
    });

    return result;
  }

  document.querySelectorAll('.filter-bar').forEach(bar => {
    const scope = bar.dataset.scope;
    bar.querySelectorAll('input, select').forEach(el => {
      el.addEventListener('input', () => rerenderScope(scope));
      el.addEventListener('change', () => rerenderScope(scope));
    });
  });

  function rerenderScope(scope) {
    if (scope === 'received') {
      renderList(document.getElementById('receivedList'), applyFilters(state.invoices.received, getFilterValues('received'), 'received'), 'received');
    } else if (scope === 'sent') {
      renderList(document.getElementById('sentList'), applyFilters(state.invoices.sent, getFilterValues('sent'), 'sent'), 'sent');
    } else if (scope === 'city') {
      renderList(document.getElementById('cityList'), applyFilters(state.cityInvoices, getFilterValues('city'), 'city'), 'city');
    }
  }

  // ----------------------------------------------------
  // Rendering: Rechnungslisten
  // ----------------------------------------------------

  function renderList(container, invoices, mode) {
    container.innerHTML = '';

    if (!invoices || invoices.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'empty-state';
      empty.textContent = mode === 'received' ? 'Keine Rechnungen gefunden.' :
                           mode === 'sent' ? 'Keine Rechnungen gefunden.' :
                           'Keine Rechnungen vorhanden.';
      container.appendChild(empty);
      return;
    }

    invoices.forEach(inv => {
      const row = document.createElement('div');
      row.className = 'invoice-row';

      const dot = document.createElement('div');
      dot.className = `status-dot ${inv.status}`;

      const info = document.createElement('div');
      info.className = 'invoice-info';

      const titleRow = document.createElement('div');
      titleRow.className = 'invoice-title-row';

      const party = document.createElement('span');
      party.className = 'invoice-party';
      party.textContent = mode === 'received' ? (inv.society_label || inv.author_name) :
                           mode === 'sent' ? inv.receiver_name :
                           `${inv.author_name} → ${inv.receiver_name}`;
      titleRow.appendChild(party);

      if (inv.society_label && mode !== 'received') {
        const tag = document.createElement('span');
        tag.className = 'invoice-tag';
        tag.textContent = inv.society_label;
        titleRow.appendChild(tag);
      }

      if (Number(inv.is_installment) === 1) {
        const tag = document.createElement('span');
        tag.className = 'installment-tag';
        tag.textContent = `RATENZAHLUNG · ${inv.installment_count}x`;
        titleRow.appendChild(tag);
      }

      if (Number(inv.insurance_covered) > 0) {
        const tag = document.createElement('span');
        tag.className = 'insurance-tag';
        tag.textContent = `Versicherung -${fmtMoney(inv.insurance_covered)}`;
        titleRow.appendChild(tag);
      }

      const meta = document.createElement('div');
      meta.className = 'invoice-meta';
      const reasonSpan = document.createElement('span');
      reasonSpan.textContent = inv.item;
      const refSpan = document.createElement('span');
      refSpan.className = 'ref-chip';
      refSpan.textContent = `#${inv.ref_id}`;
      const dateSpan = document.createElement('span');
      dateSpan.textContent = fmtDate(inv.sent_date);
      meta.appendChild(reasonSpan);
      meta.appendChild(refSpan);
      meta.appendChild(dateSpan);

      info.appendChild(titleRow);
      info.appendChild(meta);

      const amount = document.createElement('div');
      amount.className = 'invoice-amount';
      amount.style.color = inv.status === 'open' ? 'var(--violet)' : 'var(--cyan)';
      amount.textContent = fmtMoney(inv.invoice_value);

      const actions = document.createElement('div');
      actions.className = 'invoice-actions';

      if (mode === 'received' && inv.status === 'open') {
        if (Number(inv.is_installment) === 1) {
          const detailsBtn = document.createElement('button');
          detailsBtn.className = 'mini-btn details';
          detailsBtn.textContent = 'Raten anzeigen';
          detailsBtn.onclick = () => toggleInstallmentDetails(row, inv.id);
          actions.appendChild(detailsBtn);
        } else {
          const payBtn = document.createElement('button');
          payBtn.className = 'mini-btn pay';
          payBtn.textContent = 'Bezahlen';
          payBtn.onclick = () => callNui('payInvoice', { id: inv.id }).then(refreshData);
          actions.appendChild(payBtn);
        }
      }

      if (mode === 'city' && inv.status === 'open') {
        const cancelBtn = document.createElement('button');
        cancelBtn.className = 'mini-btn cancel';
        cancelBtn.textContent = 'Stornieren';
        cancelBtn.onclick = () => callNui('cancelInvoice', { id: inv.id }).then(() => loadCityInvoices());
        actions.appendChild(cancelBtn);
      }

      const pdfBtn = document.createElement('button');
      pdfBtn.className = 'mini-btn details';
      pdfBtn.textContent = 'PDF';
      pdfBtn.onclick = () => exportInvoicePDF(inv.id);
      actions.appendChild(pdfBtn);

      row.appendChild(dot);
      row.appendChild(info);
      row.appendChild(amount);
      row.appendChild(actions);
      container.appendChild(row);
    });
  }

  // ----------------------------------------------------
  // Ratenzahlung: Details ein-/ausklappen
  // ----------------------------------------------------

  async function toggleInstallmentDetails(row, invoiceId) {
    const existing = row.nextElementSibling;
    if (existing && existing.classList.contains('installment-progress')) {
      existing.remove();
      return;
    }

    const result = await callNui('getInvoiceDetail', { id: invoiceId });
    if (!result) return;

    const { invoice, installments } = result;
    const paidCount = installments.filter(p => p.status === 'paid').length;
    const percent = Math.round((paidCount / installments.length) * 100);

    const panel = document.createElement('div');
    panel.className = 'installment-progress';

    const header = document.createElement('div');
    header.style.display = 'flex';
    header.style.justifyContent = 'space-between';
    header.style.fontSize = '12px';
    header.style.color = 'var(--text-muted)';
    header.innerHTML = `<span>${paidCount} von ${installments.length} Raten bezahlt</span><span>${percent}%</span>`;
    panel.appendChild(header);

    const track = document.createElement('div');
    track.className = 'progress-track';
    const fill = document.createElement('div');
    fill.className = 'progress-fill';
    fill.style.width = `${percent}%`;
    track.appendChild(fill);
    panel.appendChild(track);

    installments.forEach(part => {
      const partRow = document.createElement('div');
      partRow.className = 'installment-part-row';

      const label = document.createElement('span');
      label.textContent = `Rate ${part.part_number}/${invoice.installment_count} · fällig ${fmtDate(part.due_date)}`;

      const right = document.createElement('div');
      right.style.display = 'flex';
      right.style.alignItems = 'center';
      right.style.gap = '10px';

      const amountSpan = document.createElement('span');
      amountSpan.className = 'part-amount';
      amountSpan.textContent = fmtMoney(part.amount);
      amountSpan.style.color = part.status === 'paid' ? 'var(--cyan)' : 'var(--violet)';
      right.appendChild(amountSpan);

      if (part.status === 'open') {
        const payPartBtn = document.createElement('button');
        payPartBtn.className = 'mini-btn pay';
        payPartBtn.textContent = 'Bezahlen';
        payPartBtn.onclick = () => callNui('payInstallment', { id: part.id }).then(() => {
          panel.remove();
          refreshData();
        });
        right.appendChild(payPartBtn);
      } else {
        const paidTag = document.createElement('span');
        paidTag.className = 'invoice-tag';
        paidTag.textContent = 'Bezahlt';
        right.appendChild(paidTag);
      }

      partRow.appendChild(label);
      partRow.appendChild(right);
      panel.appendChild(partRow);
    });

    row.after(panel);
  }

  // ----------------------------------------------------
  // Statistiken & Gesamt-Rendering
  // ----------------------------------------------------

  function renderStats() {
    const open = state.invoices.received.filter(i => i.status === 'open');
    const paid = state.invoices.received.filter(i => i.status === 'paid' || i.status === 'autopaid');
    const openSum = open.reduce((s, i) => s + Number(i.invoice_value), 0);
    const paidSum = paid.reduce((s, i) => s + Number(i.invoice_value), 0);

    document.getElementById('statOpenCount').textContent = open.length;
    document.getElementById('statOpenSum').textContent = fmtMoney(openSum);
    document.getElementById('statPaidSum').textContent = fmtMoney(paidSum);
  }

  function renderAll() {
    rerenderScope('received');
    rerenderScope('sent');
    renderStats();
  }

  function renderPlayerSelects(players) {
    ['targetSelect', 'inspectTargetSelect'].forEach(id => {
      const select = document.getElementById(id);
      select.innerHTML = '';
      if (!players || players.length === 0) {
        const opt = document.createElement('option');
        opt.textContent = 'Keine Spieler online';
        opt.disabled = true;
        select.appendChild(opt);
        return;
      }
      players.forEach(p => {
        const opt = document.createElement('option');
        opt.value = p.id;
        opt.textContent = `[${p.id}] ${p.name}`;
        select.appendChild(opt);
      });
    });

    renderGroupPlayerList();
  }

  // ----------------------------------------------------
  // Kontext: Rechte, Society-Zugehörigkeit, Presets
  // ----------------------------------------------------

  function applyContext(context) {
    state.context = context;
    if (!context) return;

    document.getElementById('navInspect').classList.toggle('hidden-view', !context.canInspect);
    document.getElementById('navCity').classList.toggle('hidden-view', !context.canManage);
    document.getElementById('navTeam').classList.toggle('hidden-view', !context.society);
    document.getElementById('navGroup').classList.toggle('hidden-view', !context.groupInvoiceEnabled);

    const toggleSociety = document.getElementById('toggleSociety');
    if (context.society) {
      toggleSociety.classList.remove('hidden-view');
      toggleSociety.textContent = context.society.label;
    } else {
      toggleSociety.classList.add('hidden-view');
      state.selectedType = 'personal';
      document.querySelector('.toggle-btn[data-type="personal"]').classList.add('active');
      toggleSociety.classList.remove('active');
    }

    updatePresetDropdown();
    updateInstallmentVisibility();
  }

  function updatePresetDropdown() {
    const presetSelect = document.getElementById('presetAddSelect');
    presetSelect.innerHTML = '<option value="">Vorlage hinzufügen...</option>';

    if (state.selectedType === 'society' && state.context && state.context.society) {
      presetSelect.classList.remove('hidden-view');
      state.context.society.items.forEach(item => {
        const opt = document.createElement('option');
        opt.value = JSON.stringify(item);
        opt.textContent = `${item.label} — ${fmtMoney(item.price)}`;
        presetSelect.appendChild(opt);
      });
    } else {
      presetSelect.classList.add('hidden-view');
    }
  }

  presetAddSelectListener();
  function presetAddSelectListener() {
    document.getElementById('presetAddSelect').addEventListener('change', (e) => {
      if (!e.target.value) return;
      const item = JSON.parse(e.target.value);
      addItemRow(item.label, item.price);
      e.target.value = '';
    });
  }

  document.querySelectorAll('.toggle-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      if (btn.classList.contains('hidden-view')) return;
      document.querySelectorAll('.toggle-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      state.selectedType = btn.dataset.type;
      updatePresetDropdown();
      updateInstallmentVisibility();
    });
  });

  // ----------------------------------------------------
  // Mehrfachpositionen: Item-Zeilen
  // ----------------------------------------------------

  function addItemRow(label, price) {
    const id = 'item_' + Math.random().toString(36).slice(2, 9);
    state.items.push({ id, label: label || '', price: price || '' });
    renderItemRows();
  }

  function removeItemRow(id) {
    state.items = state.items.filter(i => i.id !== id);
    if (state.items.length === 0) addItemRow();
    renderItemRows();
  }

  function renderItemRows() {
    const container = document.getElementById('itemsContainer');
    container.innerHTML = '';

    state.items.forEach(item => {
      const row = document.createElement('div');
      row.className = 'item-row';

      const labelInput = document.createElement('input');
      labelInput.type = 'text';
      labelInput.placeholder = 'Grund / Position';
      labelInput.value = item.label;
      labelInput.oninput = (e) => { item.label = e.target.value; };

      const priceInput = document.createElement('input');
      priceInput.type = 'number';
      priceInput.min = '1';
      priceInput.placeholder = '$';
      priceInput.value = item.price;
      priceInput.oninput = (e) => { item.price = e.target.value; updateItemsTotal(); updateInstallmentVisibility(); };

      const removeBtn = document.createElement('button');
      removeBtn.className = 'remove-item-btn';
      removeBtn.textContent = '✕';
      removeBtn.onclick = () => removeItemRow(item.id);

      row.appendChild(labelInput);
      row.appendChild(priceInput);
      row.appendChild(removeBtn);
      container.appendChild(row);
    });

    updateItemsTotal();
  }

  function updateItemsTotal() {
    const total = state.items.reduce((s, i) => s + (Number(i.price) || 0), 0);
    document.getElementById('itemsTotal').textContent = fmtMoney(total);
    return total;
  }

  document.getElementById('addItemBtn').addEventListener('click', () => addItemRow());

  // ----------------------------------------------------
  // Ratenzahlung im Formular
  // ----------------------------------------------------

  function updateInstallmentVisibility() {
    const box = document.getElementById('installmentBox');
    const cfg = state.context;
    const total = state.items.reduce((s, i) => s + (Number(i.price) || 0), 0);

    if (!cfg || !cfg.installmentsEnabled || total < cfg.installmentsMinAmount) {
      box.classList.add('hidden-view');
      document.getElementById('installmentToggle').checked = false;
      document.getElementById('installmentPartsField').classList.add('hidden-view');
      return;
    }

    box.classList.remove('hidden-view');

    const partsSelect = document.getElementById('installmentPartsSelect');
    if (partsSelect.options.length === 0) {
      for (let i = 2; i <= cfg.installmentsMaxParts; i++) {
        const opt = document.createElement('option');
        opt.value = i;
        opt.textContent = `${i} Raten`;
        partsSelect.appendChild(opt);
      }
    }
  }

  document.getElementById('installmentToggle').addEventListener('change', (e) => {
    document.getElementById('installmentPartsField').classList.toggle('hidden-view', !e.target.checked);
  });

  // ----------------------------------------------------
  // Neue Rechnung senden
  // ----------------------------------------------------

  document.getElementById('sendInvoiceBtn').addEventListener('click', () => {
    const targetId = document.getElementById('targetSelect').value;
    const notes = document.getElementById('notesInput').value.trim();
    const society = state.selectedType === 'society' && state.context.society ? state.context.society.key : '';

    const items = state.items
      .filter(i => i.label.trim() && Number(i.price) > 0)
      .map(i => ({ label: i.label.trim(), price: Number(i.price) }));

    if (!targetId || items.length === 0) return;

    const installmentChecked = document.getElementById('installmentToggle').checked;
    const installmentParts = installmentChecked ? document.getElementById('installmentPartsSelect').value : null;

    callNui('sendInvoice', { targetId, items, society, notes, installmentParts }).then(() => {
      state.items = [];
      addItemRow();
      document.getElementById('notesInput').value = '';
      document.getElementById('installmentToggle').checked = false;
      document.getElementById('installmentPartsField').classList.add('hidden-view');
      refreshData();
    });
  });

  // Startzustand: eine leere Position
  addItemRow();

  // ----------------------------------------------------
  // Gruppenrechnung
  // ----------------------------------------------------

  function renderGroupPlayerList() {
    const container = document.getElementById('groupPlayerList');
    container.innerHTML = '';

    if (!state.players || state.players.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'empty-state';
      empty.textContent = 'Keine Spieler online.';
      container.appendChild(empty);
      return;
    }

    state.players.forEach(p => {
      const row = document.createElement('label');
      row.className = 'group-player-row';

      const checkbox = document.createElement('input');
      checkbox.type = 'checkbox';
      checkbox.checked = state.groupSelected.has(p.id);
      checkbox.onchange = () => {
        if (checkbox.checked) state.groupSelected.add(p.id);
        else state.groupSelected.delete(p.id);
        updateGroupShare();
      };

      const name = document.createElement('span');
      name.textContent = `[${p.id}] ${p.name}`;

      row.appendChild(checkbox);
      row.appendChild(name);
      container.appendChild(row);
    });
  }

  function updateGroupShare() {
    const total = Number(document.getElementById('groupAmountInput').value) || 0;
    const count = state.groupSelected.size;
    const share = count > 0 ? Math.floor(total / count) : 0;
    document.getElementById('groupShareLabel').textContent = `Anteil pro Person (${count} Spieler)`;
    document.getElementById('groupShareValue').textContent = fmtMoney(share);
  }

  document.getElementById('groupAmountInput').addEventListener('input', updateGroupShare);

  document.getElementById('sendGroupBtn').addEventListener('click', () => {
    const item = document.getElementById('groupItemInput').value.trim();
    const amount = document.getElementById('groupAmountInput').value;
    const notes = document.getElementById('groupNotesInput').value.trim();
    const targetIds = Array.from(state.groupSelected);

    if (!item || !amount || Number(amount) <= 0 || targetIds.length === 0) return;

    callNui('sendGroupInvoice', { targetIds, amount, item, notes }).then(() => {
      document.getElementById('groupItemInput').value = '';
      document.getElementById('groupAmountInput').value = '';
      document.getElementById('groupNotesInput').value = '';
      state.groupSelected.clear();
      renderGroupPlayerList();
      updateGroupShare();
      refreshData();
    });
  });

  // ----------------------------------------------------
  // Alle bezahlen
  // ----------------------------------------------------

  document.getElementById('payAllBtn').addEventListener('click', () => {
    callNui('payAllInvoices').then(refreshData);
  });

  // ----------------------------------------------------
  // Referenz bezahlen
  // ----------------------------------------------------

  document.getElementById('refCodeInput').addEventListener('input', (e) => {
    e.target.value = e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, '');
  });

  document.getElementById('payReferenceBtn').addEventListener('click', () => {
    const refId = document.getElementById('refCodeInput').value.trim();
    if (!refId) return;
    callNui('payByReference', { refId }).then(() => {
      document.getElementById('refCodeInput').value = '';
      refreshData();
    });
  });

  // ----------------------------------------------------
  // Spieler prüfen
  // ----------------------------------------------------

  document.getElementById('inspectBtn').addEventListener('click', async () => {
    const targetId = document.getElementById('inspectTargetSelect').value;
    if (!targetId) return;

    const result = await callNui('inspectPlayer', { targetId });
    const container = document.getElementById('inspectResult');
    container.innerHTML = '';

    if (!result) {
      const empty = document.createElement('div');
      empty.className = 'empty-state';
      empty.textContent = 'Keine Berechtigung oder Spieler nicht gefunden.';
      container.appendChild(empty);
      return;
    }

    const summary = document.createElement('div');
    summary.className = 'inspect-summary';
    summary.innerHTML = `
      <div class="stat-card"><span class="stat-label">Spieler</span><span class="stat-value" style="font-size:15px;font-family:'Inter',sans-serif;">${result.name}</span></div>
      <div class="stat-card"><span class="stat-label">Offene Rechnungen</span><span class="stat-value">${result.count}</span></div>
      <div class="stat-card accent"><span class="stat-label">Offene Summe</span><span class="stat-value">${fmtMoney(result.total)}</span></div>
    `;
    container.appendChild(summary);

    const list = document.createElement('div');
    list.className = 'invoice-list';
    container.appendChild(list);
    renderList(list, result.invoices, 'inspect');
  });

  // ----------------------------------------------------
  // Team-Dashboard / Leaderboard
  // ----------------------------------------------------

  async function loadLeaderboard() {
    const result = await callNui('getSocietyLeaderboard');
    const container = document.getElementById('leaderboardList');
    container.innerHTML = '';

    if (!result) {
      const empty = document.createElement('div');
      empty.className = 'empty-state';
      empty.textContent = 'Keine Society-Zugehörigkeit oder keine Daten.';
      container.appendChild(empty);
      return;
    }

    document.getElementById('teamSubtitle').textContent = `Umsatz & Anzahl Rechnungen · ${result.society}`;
    document.getElementById('teamOpenCount').textContent = result.openCount;

    if (!result.rows || result.rows.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'empty-state';
      empty.textContent = 'Noch keine bezahlten Rechnungen für dieses Team.';
      container.appendChild(empty);
      return;
    }

    result.rows.forEach((row, index) => {
      const el = document.createElement('div');
      el.className = 'leaderboard-row';
      el.innerHTML = `
        <span class="leaderboard-rank">${index + 1}</span>
        <span class="leaderboard-name">${row.author_name}</span>
        <span class="leaderboard-count">${row.invoice_count} Rechnungen</span>
        <span class="leaderboard-revenue">${fmtMoney(row.total_revenue)}</span>
      `;
      container.appendChild(el);
    });
  }

  document.getElementById('refreshTeamBtn').addEventListener('click', loadLeaderboard);

  // ----------------------------------------------------
  // Stadt-Rechnungen
  // ----------------------------------------------------

  async function loadCityInvoices() {
    const result = await callNui('getCityInvoices');
    state.cityInvoices = result || [];
    rerenderScope('city');
  }

  document.getElementById('refreshCityBtn').addEventListener('click', loadCityInvoices);

  // ----------------------------------------------------
  // PDF-Export
  // ----------------------------------------------------

  async function exportInvoicePDF(invoiceId) {
    const result = await callNui('getInvoiceDetail', { id: invoiceId });
    if (!result || !window.jspdf) {
      console.warn('PDF-Export nicht möglich (keine Daten oder jsPDF nicht geladen).');
      return;
    }

    const { invoice, items, installments } = result;
    const { jsPDF } = window.jspdf;
    const doc = new jsPDF();

    doc.setFontSize(18);
    doc.text('Rechnung', 14, 20);

    doc.setFontSize(10);
    doc.text(`Referenz: ${invoice.ref_id}`, 14, 30);
    doc.text(`Datum: ${fmtDate(invoice.sent_date)}`, 14, 36);
    doc.text(`Von: ${invoice.society_label || invoice.author_name}`, 14, 44);
    doc.text(`An: ${invoice.receiver_name}`, 14, 50);
    if (invoice.notes) doc.text(`Notiz: ${invoice.notes}`, 14, 56);

    let y = 68;
    doc.setFontSize(11);
    doc.text('Position', 14, y);
    doc.text('Betrag', 170, y, { align: 'right' });
    y += 4;
    doc.line(14, y, 196, y);
    y += 6;

    const lineItems = (items && items.length > 0) ? items : [{ label: invoice.item, price: invoice.original_value || invoice.invoice_value }];
    lineItems.forEach(it => {
      doc.text(String(it.label), 14, y);
      doc.text(fmtMoney(it.price), 170, y, { align: 'right' });
      y += 7;
    });

    y += 2;
    doc.line(14, y, 196, y);
    y += 8;

    if (Number(invoice.insurance_covered) > 0) {
      doc.text('Von Versicherung übernommen:', 14, y);
      doc.text(`-${fmtMoney(invoice.insurance_covered)}`, 170, y, { align: 'right' });
      y += 7;
    }

    doc.setFontSize(13);
    doc.text('Zu zahlen:', 14, y);
    doc.text(fmtMoney(invoice.invoice_value), 170, y, { align: 'right' });
    y += 10;

    if (installments && installments.length > 0) {
      doc.setFontSize(11);
      doc.text('Ratenplan:', 14, y);
      y += 6;
      doc.setFontSize(9);
      installments.forEach(part => {
        doc.text(`Rate ${part.part_number}/${invoice.installment_count} · fällig ${fmtDate(part.due_date)} · ${part.status === 'paid' ? 'bezahlt' : 'offen'}`, 14, y);
        doc.text(fmtMoney(part.amount), 170, y, { align: 'right' });
        y += 6;
      });
    }

    doc.setFontSize(8);
    doc.setTextColor(150);
    doc.text('Erstellt mit esx_rechnungen', 14, 285);

    doc.save(`Rechnung_${invoice.ref_id}.pdf`);
  }

  // ----------------------------------------------------
  // Daten laden
  // ----------------------------------------------------

  function refreshData() {
    callNui('refreshData');
  }

  // ----------------------------------------------------
  // Nachrichten vom Client-Lua
  // ----------------------------------------------------

  window.addEventListener('message', (event) => {
    const { action, data } = event.data;

    switch (action) {
      case 'open':
        app.classList.remove('hidden');
        break;
      case 'close':
        app.classList.add('hidden');
        break;
      case 'setInvoices':
        state.invoices = data;
        renderAll();
        break;
      case 'setPlayers':
        state.players = data;
        renderPlayerSelects(data);
        break;
      case 'setContext':
        applyContext(data);
        break;
    }
  });
})();
