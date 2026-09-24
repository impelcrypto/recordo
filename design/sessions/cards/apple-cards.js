// Static prototype only: fictional cards live in memory, Reset restores the fixture.
// Nothing is read from or written to real Recordo data.
(function(){
  'use strict';

  // Fixed clock so 今日 / 明日 / 出題待ち read the same whatever day the mock is opened.
  var NOW = new Date(2026, 8, 24, 19, 42);
  var HOUR = 3600e3;
  function at(month, day, h, m){ return new Date(2026, month - 1, day, h, m); }
  function C(term, tag, box, due, asked, definition){
    return { id:term, term:term, tags:tag ? [tag] : [], box:box, due:due, definition:definition,
             asked:asked.map(function(a){ return { at:a[0], project:a[1], via:a[2] }; }) };
  }

  var BASE = [
    C('LCP', 'Web性能', 0, at(9,24,16,20), [[at(9,24,16,20),'sample-app','term']],
      'Largest Contentful Paint の略。ページの中でいちばん大きな画像や文字のかたまりが表示されるまでの時間で、読み込みの体感速度を測る Core Web Vitals の指標のひとつ。'),
    C('CRDT', '分散システム', 0, at(9,23,21,48), [[at(9,8,10,2),'notes-api','btw'],[at(9,23,21,48),'notes-api','prompt']],
      'Conflict-free Replicated Data Type の略。複数の端末で同時に書き換えても、同期すれば必ず同じ状態にそろうよう作られたデータ構造。共同編集で使われる。'),
    C('idempotent', 'API設計', 2, at(9,25,9,0), [[at(9,23,14,2),'notes-api','btw']],
      '同じ操作を何回くり返しても、1回だけ行ったときと結果が変わらない性質。リトライで二重に処理されないよう、PUT や DELETE はこうなるように作る。'),
    C('backpressure', 'ストリーム処理', 3, at(9,27,14,0), [[at(9,22,10,31),'web-shop','btw']],
      '受け手の処理が追いつかないとき、送り手に速度を落とすよう知らせる仕組み。途中のバッファがあふれてメモリを使い切るのを防ぐ。'),
    C('tail latency', 'Web性能', 1, at(9,24,22,10), [[at(9,21,17,40),'web-shop','prompt']],
      '応答時間の分布のうち、遅い側の端（p99 など）のこと。平均が速くても一部の利用者は長く待たされるため、平均とは別に見る。'),
    C('debounce', 'フロントエンド', 4, at(10,1,9,15), [[at(9,21,9,12),'sample-app','term']],
      '入力が止まってから一定時間たったときに、一度だけ処理を実行する手法。検索欄で1文字打つごとに通信しないために使う。'),
    C('Nagle’s algorithm', 'ネットワーク', 2, at(9,25,13,30), [[at(9,20,15,55),'notes-api','btw']],
      '小さなパケットをまとめてから送る TCP の仕組み。通信の回数は減るが、少しずつやりとりする通信では latency が増えることがある。'),
    C('optimistic update', 'フロントエンド', 0, at(9,19,18,7), [[at(9,19,18,7),'web-shop','term']],
      'サーバーの応答を待たずに、成功した前提で先に画面を更新するやり方。失敗が返ってきたら元の表示に戻す。'),
    C('head-of-line blocking', 'ネットワーク', 5, at(10,13,9,0), [[at(9,12,11,26),'sample-app','prompt']],
      '列の先頭の処理が詰まると、後ろに並んだものまで全部待たされる現象。HTTP/1.1 のパイプラインや TCP の再送で起きる。'),
    C('template literal', 'JavaScript', 6, at(10,20,9,0), [[at(8,30,13,45),'sample-app','btw']],
      'バッククォートで囲む文字列の書き方。${} の中に式を埋め込めて、改行もそのまま書ける。'),
    C('memoization', 'アルゴリズム', 6, at(10,18,20,10), [[at(8,25,16,3),'notes-api','term']],
      '一度計算した結果を覚えておき、同じ引数で呼ばれたときは計算し直さずにその結果を返す手法。'),
    C('exponential backoff', 'API設計', 6, at(10,9,8,40), [[at(8,19,10,18),'web-shop','prompt']],
      '失敗したリトライの間隔を、1秒、2秒、4秒と倍に広げていくやり方。混んでいるサーバーをさらに詰まらせないために使う。')
  ];

  // Deterministic 240 cards; every 4th is learned, so the 60 learned ones straddle pages 2 and 3.
  function manyCards(){
    var out = [];
    for(var i = 0; i < 240; i++){
      var b = BASE[i % BASE.length], round = Math.floor(i / BASE.length);
      var askedAt = new Date(+NOW - i * 5 * HOUR), box = i % 4 === 0 ? 6 : i % 6;
      out.push({ id:'m' + i, term:round ? b.term + ' ' + (round + 1) : b.term, tags:b.tags, box:box,
                 due:box === 0 ? askedAt : new Date(+NOW + ((i % 9) - 2) * 9 * HOUR), definition:b.definition,
                 asked:[{ at:askedAt, project:b.asked[0].project, via:b.asked[0].via }] });
    }
    return out;
  }

  // Critically damped spring x(t)=1-(1+wt)e^-wt, w=2π/response: SwiftUI .spring(response:.25, dampingFraction:1).
  var SPRING_MS = 360;
  var SPRING = 'linear(' + Array.from({ length:25 }, function(_, i){
    var wt = (2 * Math.PI / 0.25) * (i / 24) * SPRING_MS / 1000;
    return i === 24 ? '1' : (1 - (1 + wt) * Math.exp(-wt)).toFixed(4);
  }).join(',') + ')';

  var desktop = document.getElementById('desktop');
  var win = document.getElementById('win');
  var scroll = document.getElementById('scroll');
  var body = document.getElementById('body');
  var titleEl = document.getElementById('page-title');
  var totalEl = document.getElementById('total');
  var searchField = document.getElementById('search-field');
  var search = document.getElementById('search');
  var searchClear = document.getElementById('search-clear');
  var syncNote = document.getElementById('sync-note');
  var scrim = document.getElementById('scrim');
  var alertEl = document.getElementById('alert');
  var alertDiscard = document.getElementById('alert-discard');
  var alertCancel = document.getElementById('alert-cancel');
  var pager = document.getElementById('pager');
  var pagePrev = document.getElementById('page-prev');
  var pageNext = document.getElementById('page-next');
  var ctl = {};
  ['state','page','theme','text','motion','lang'].forEach(function(k){ ctl[k] = document.getElementById('ctl-' + k); });

  var model = { theme:'light', text:'100', motion:'full', lang:'ja' };
  var st = { id:'normal', cards:[], query:'', page:1, pages:1, syncing:false, unreadable:false, alertFor:null };
  var PAGE_SIZE = 100;

  function tr(ja, en){ return model.lang === 'en' ? en : ja; }
  function esc(s){ return String(s).replace(/[&<>"]/g, function(c){ return { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;' }[c]; }); }
  function reduce(){ return model.motion === 'reduce'; }

  // ---------- text formats (ports of AppModel.when, QuizSession.meta / source) ----------

  function sameDay(a, b){ return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate(); }
  function when(d){
    var t = d.getHours() + ':' + String(d.getMinutes()).padStart(2, '0');
    if(sameDay(d, NOW)) return tr('今日 ' + t, 'today at ' + t);
    if(sameDay(d, new Date(NOW.getFullYear(), NOW.getMonth(), NOW.getDate() + 1))) return tr('明日 ' + t, 'tomorrow at ' + t);
    return (d.getMonth() + 1) + '/' + d.getDate() + ' ' + t;
  }
  function metaHTML(c){
    var next = c.due <= NOW
      ? '<strong class="due-now">' + tr('出題待ち', 'Due now') + '</strong>'
      : tr('次の出題 ', 'Next: ') + when(c.due);
    return esc(c.tags[0] || tr('未分類', 'Uncategorized')) + ' · ' + tr('段', 'Box') + ' ' + c.box + ' · ' + next;
  }
  function source(c){
    var a = c.asked[c.asked.length - 1];
    var how = { btw:tr('/btw で質問', 'asked via /btw'), term:tr('/term で質問', 'asked via /term'), prompt:tr('会話で質問', 'asked in chat') }[a.via];
    return (a.at.getMonth() + 1) + '/' + a.at.getDate() + ' · ' + a.project + ' · ' + how;
  }
  function lastAsked(c){ return +c.asked[c.asked.length - 1].at; }
  function isLearned(c){ return c.box >= 6; }
  function notLearned(c){ return c.box < 6; }
  // One sequence (Learning, then Learned, each most recently asked first) that pages cut into 100s.
  function ordered(cards){
    var byRecent = function(a, b){ return lastAsked(b) - lastAsked(a); };
    return cards.filter(notLearned).sort(byRecent).concat(cards.filter(isLearned).sort(byRecent));
  }

  // ---------- rendering ----------

  function matches(){
    var q = st.query.trim().toLowerCase();
    if(!q) return st.cards;
    return st.cards.filter(function(c){ return c.term.toLowerCase().indexOf(q) >= 0 || c.definition.toLowerCase().indexOf(q) >= 0; });
  }

  function rowHTML(c){
    var label = tr(c.term + ' を捨てる', 'Discard ' + c.term);
    var off = st.syncing ? ' aria-disabled="true" aria-describedby="sync-note"' : '';
    return '<li class="card-row" data-flip="' + esc(c.id) + '">' +
      '<div><p class="card-term">' + esc(c.term) + '</p>' +
      '<p class="card-def">' + esc(c.definition) + '</p>' +
      '<p class="card-meta">' + metaHTML(c) + '</p>' +
      '<p class="card-source">' + esc(source(c)) + '</p></div>' +
      '<button type="button" class="card-trash" data-id="' + esc(c.id) + '" aria-label="' + esc(label) + '" title="' + esc(label) + '"' + off + '>' +
      '<svg aria-hidden="true"><use href="#i-trash"></use></svg></button></li>';
  }

  // Counts are always whole-list. A section with no matches keeps its 0 / N head on one page only.
  function sectionHTML(key, title, note, all, matched, rows, holdsEmpty){
    if(!all.length || (!rows.length && !(holdsEmpty && !matched.length))) return '';
    var count = st.query.trim() ? matched.length + ' / ' + all.length : String(all.length);
    return '<section class="section" aria-labelledby="h-' + key + '">' +
      '<div class="section-head" data-flip="head-' + key + '">' +
        '<div class="section-title"><h2 id="h-' + key + '">' + title + '</h2><span class="section-count">' + count + '</span></div>' +
        (note ? '<p class="section-note">' + note + '</p>' : '') +
      '</div>' +
      '<ul class="card-list">' + rows.map(rowHTML).join('') + '</ul></section>';
  }

  function notice(title, text, action){
    return '<div class="notice" data-flip="notice"><p class="notice-title">' + esc(title) + '</p>' +
      (text ? '<p>' + esc(text) + '</p>' : '') +
      (action ? '<button type="button" class="btn-bordered" data-action="clear-search">' + esc(action) + '</button>' : '') + '</div>';
  }

  function listHTML(){
    if(st.unreadable){
      return notice(tr('cards.json を読めませんでした', 'Couldn’t read cards.json'),
        tr('ファイルを直すまで、取り込みと出題を止めています。', 'Syncing and quizzes are paused until the file is fixed.'));
    }
    if(!st.cards.length){
      return notice(tr('まだカードがありません', 'No cards yet'),
        tr('Claude Code で用語の意味を聞くと、次の同期でカードになります。', 'Ask Claude Code what a term means, and it becomes a card at the next sync.'));
    }
    var shown = ordered(matches());
    if(!shown.length){
      var q = st.query.trim();
      return notice(tr('“' + q + '” に合うカードはありません', 'No cards match “' + q + '”.'), '', tr('検索を消す', 'Clear search'));
    }
    st.pages = Math.ceil(shown.length / PAGE_SIZE);
    st.page = Math.min(Math.max(st.page, 1), st.pages);
    var rows = shown.slice((st.page - 1) * PAGE_SIZE, st.page * PAGE_SIZE);
    return sectionHTML('learning', tr('覚えている途中', 'Learning'), '', st.cards.filter(notLearned), shown.filter(notLearned), rows.filter(notLearned), st.page === 1) +
      sectionHTML('learned', tr('覚えた', 'Learned'), tr('30日ごとに出題します', 'Asked again every 30 days'), st.cards.filter(isLearned), shown.filter(isLearned), rows.filter(isLearned), st.page === st.pages);
  }

  function renderBody(){
    st.pages = 1;
    body.innerHTML = listHTML();
    st.page = Math.min(Math.max(st.page, 1), st.pages);
    pager.hidden = st.pages < 2;
    pagePrev.textContent = tr('‹ 前へ', '‹ Previous');
    pageNext.textContent = tr('次へ ›', 'Next ›');
    pagePrev.setAttribute('aria-disabled', String(st.page === 1));
    pageNext.setAttribute('aria-disabled', String(st.page === st.pages));
    document.getElementById('page-label').textContent = st.page + ' / ' + st.pages;
    pager.setAttribute('aria-label', tr('ページ', 'Pages'));
    ctl.page.innerHTML = Array.from({ length:st.pages }, function(_, i){ return '<option>' + (i + 1) + '</option>'; }).join('');
    ctl.page.value = String(st.page);
    syncURL();
  }

  function renderHead(){
    var n = st.cards.length, hasList = !st.unreadable && n > 0;
    titleEl.textContent = tr('カード', 'Cards');
    totalEl.hidden = !hasList;
    totalEl.textContent = tr(n + ' 枚', n === 1 ? '1 card' : n + ' cards');
    searchField.hidden = !hasList;
    search.placeholder = tr('用語や定義で探す', 'Search terms and definitions');
    search.setAttribute('aria-label', search.placeholder);
    if(search.value !== st.query) search.value = st.query; // keep the caret when the input itself is the source
    searchClear.hidden = !st.query;
    searchClear.setAttribute('aria-label', tr('検索を消す', 'Clear search'));
    syncNote.hidden = !(st.syncing && hasList);
    syncNote.querySelector('[data-slot=text]').textContent = tr('同期中はカードを捨てられません', 'Cards can’t be discarded while syncing.');
  }

  function fillAlert(){
    var c = find(st.alertFor);
    document.getElementById('alert-title').textContent = tr('“' + c.term + '” を捨てますか？', 'Discard “' + c.term + '”?');
    document.getElementById('alert-msg').textContent = tr('段と回答の記録も消えます。元に戻せません。', 'Its box and answer history are deleted too. This can’t be undone.');
    alertDiscard.textContent = tr('捨てる', 'Discard');
    alertCancel.textContent = tr('キャンセル', 'Cancel');
  }

  function render(){
    desktop.setAttribute('data-theme', model.theme);
    desktop.setAttribute('data-text', model.text);
    desktop.setAttribute('data-motion', model.motion);
    document.documentElement.lang = model.lang;
    renderHead();
    renderBody();
    if(st.alertFor) fillAlert();
    syncControls();
    syncURL();
  }

  function syncControls(){
    ctl.state.value = st.id;
    ['theme','text','motion','lang'].forEach(function(k){ ctl[k].value = model[k]; });
  }
  function syncURL(){
    var p = new URLSearchParams({ state:st.id, page:st.page, theme:model.theme, text:model.text, motion:model.motion, lang:model.lang });
    history.replaceState(null, '', '?' + p.toString());
  }

  // ---------- discard ----------

  function find(id){ return st.cards.filter(function(c){ return c.id === id; })[0]; }
  function trashFor(id){ return body.querySelector('.card-trash[data-id="' + CSS.escape(id) + '"]'); }

  var FLIP = '#body [data-flip]:not(.ghost), #pager [data-flip]';
  // On-screen rects include any in-flight transform, so a second discard mid-reflow starts from where rows are drawn.
  function captureLayout(){
    var view = scroll.getBoundingClientRect(), out = {};
    scroll.querySelectorAll(FLIP).forEach(function(el){
      var r = el.getBoundingClientRect();
      if(r.bottom >= view.top && r.top <= view.bottom) out[el.getAttribute('data-flip')] = r.top;
    });
    body.getAnimations({ subtree:true }).concat(pager.getAnimations({ subtree:true })).forEach(function(a){ a.cancel(); });
    return out;
  }
  function animateFrom(before){
    if(reduce()) return;
    scroll.querySelectorAll(FLIP).forEach(function(el){
      var top = before[el.getAttribute('data-flip')];
      if(top === undefined) return;
      var dy = top - el.getBoundingClientRect().top;
      if(Math.abs(dy) >= 0.5) el.animate([{ transform:'translateY(' + dy + 'px)' }, { transform:'none' }], { duration:SPRING_MS, easing:SPRING });
    });
  }
  // The removed row fades where it was while the rows below slide up underneath it (SwiftUI's default .opacity removal).
  function ghost(row, rect){
    var host = body.getBoundingClientRect();
    row.classList.add('ghost');
    row.inert = true;
    row.style.cssText = 'top:' + (rect.top - host.top) + 'px;left:' + (rect.left - host.left) + 'px;width:' + rect.width + 'px';
    body.appendChild(row);
    row.animate([{ opacity:1 }, { opacity:0 }], { duration:150, easing:'ease-out', fill:'forwards' }).finished
      .then(function(){ row.remove(); }, function(){ row.remove(); });
  }

  function discard(id){
    var order = Array.prototype.map.call(body.querySelectorAll('.card-trash'), function(b){ return b.dataset.id; });
    var i = order.indexOf(id);
    var next = order[i + 1] || order[i - 1];
    var oldRow = trashFor(id).closest('.card-row');
    var oldRect = oldRow.getBoundingClientRect();
    var before = captureLayout();
    st.cards = st.cards.filter(function(c){ return c.id !== id; });
    renderHead();
    renderBody();
    ghost(oldRow, oldRect);
    animateFrom(before);
    // Focus moves now, not after the animation. If the page emptied, the last row of the page it fell back to is the previous row.
    var trashes = body.querySelectorAll('.card-row:not(.ghost) .card-trash');
    var target = (next && trashFor(next)) || trashes[trashes.length - 1] || body.querySelector('[data-action=clear-search]') || titleEl;
    target.focus();
  }

  // ---------- alert sheet ----------

  function openAlert(id){
    st.alertFor = id;
    fillAlert();
    alertEl.getAnimations().forEach(function(a){ a.cancel(); });
    alertEl.hidden = false;
    scrim.hidden = false;
    scroll.inert = true;
    alertEl.animate(reduce()
      ? [{ opacity:0 }, { opacity:1 }]
      : [{ opacity:0, transform:'translateY(-8px) scale(.97)' }, { opacity:1, transform:'none' }],
      { duration:reduce() ? 150 : SPRING_MS, easing:reduce() ? 'ease-out' : SPRING });
    scrim.animate([{ opacity:0 }, { opacity:1 }], { duration:150 });
    alertCancel.focus();
  }
  function closeAlert(){
    st.alertFor = null;
    scroll.inert = false;
    scrim.hidden = true;
    // Leaves along the path it came in on, then hides; a reopen cancels this.
    var out = alertEl.animate(reduce()
      ? [{ opacity:1 }, { opacity:0 }]
      : [{ opacity:1, transform:'none' }, { opacity:0, transform:'translateY(-8px) scale(.97)' }],
      { duration:150, easing:'ease-in', fill:'forwards' });
    out.finished.then(function(){ if(!st.alertFor) alertEl.hidden = true; out.cancel(); }, function(){});
  }
  function cancelAlert(){
    var id = st.alertFor;
    closeAlert();
    var b = trashFor(id); if(b) b.focus();
  }

  alertCancel.addEventListener('click', cancelAlert);
  alertDiscard.addEventListener('click', function(){ var id = st.alertFor; closeAlert(); discard(id); });
  document.addEventListener('keydown', function(e){
    if(!st.alertFor) return;
    if(e.key === 'Escape'){ e.preventDefault(); cancelAlert(); }
    else if(e.key === 'Tab'){ e.preventDefault(); (document.activeElement === alertCancel ? alertDiscard : alertCancel).focus(); }
  });

  // ---------- list interactions ----------

  body.addEventListener('click', function(e){
    var trash = e.target.closest('.card-trash');
    if(trash){ if(trash.getAttribute('aria-disabled') !== 'true') openAlert(trash.dataset.id); return; }
    if(e.target.closest('[data-action=clear-search]')) clearSearch();
  });
  function clearSearch(){
    st.query = '';
    st.page = 1;
    renderHead(); renderBody();
    search.focus();
  }
  search.addEventListener('input', function(){ st.query = search.value; st.page = 1; renderHead(); renderBody(); });
  search.addEventListener('keydown', function(e){ if(e.key === 'Escape' && st.query){ e.preventDefault(); clearSearch(); } });
  searchClear.addEventListener('click', clearSearch);
  // The pressed button keeps focus (aria-disabled, not disabled, so it stays focusable at either end).
  function goPage(page, btn){
    st.page = page;
    renderBody();
    if(btn) btn.focus({ preventScroll:true });
    scroll.scrollTo({ top:0, behavior:reduce() ? 'auto' : 'smooth' });
  }
  pagePrev.addEventListener('click', function(){ if(st.page > 1) goPage(st.page - 1, pagePrev); });
  pageNext.addEventListener('click', function(){ if(st.page < st.pages) goPage(st.page + 1, pageNext); });
  ctl.page.addEventListener('change', function(){ goPage(Number(ctl.page.value)); });
  scroll.addEventListener('scroll', function(){ win.toggleAttribute('data-scrolled', scroll.scrollTop > 0); });

  // ---------- fixture ----------

  function enterState(id, page){
    st.id = id;
    st.page = page || 1;
    st.cards = id === 'empty' ? [] : id === 'many' ? manyCards() : BASE.slice();
    st.query = id === 'search' ? 'late' : id === 'no-match' ? 'xyz' : '';
    st.syncing = id === 'syncing';
    st.unreadable = id === 'unreadable';
    st.alertFor = null;
    alertEl.hidden = true; scrim.hidden = true; scroll.inert = false;
    render();
    scroll.scrollTop = 0;
    win.removeAttribute('data-scrolled');
    if(id === 'confirm') openAlert(body.querySelector('.card-trash').dataset.id);
  }

  ctl.state.addEventListener('change', function(){ enterState(ctl.state.value); });
  ['theme','text','motion','lang'].forEach(function(k){
    ctl[k].addEventListener('change', function(){ model[k] = ctl[k].value; render(); });
  });
  document.getElementById('ctl-reset').addEventListener('click', function(){ enterState(st.id); });

  // ---------- init from URL ----------
  var qs = new URLSearchParams(location.search);
  model.theme = qs.get('theme') === 'dark' ? 'dark' : 'light';
  model.text = qs.get('text') === '200' ? '200' : '100';
  model.lang = qs.get('lang') === 'en' ? 'en' : 'ja';
  // The toolbar is authoritative; the OS setting only seeds the default when the URL is silent.
  var motionParam = qs.get('motion');
  model.motion = motionParam === 'reduce' || motionParam === 'full' ? motionParam
    : (window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'reduce' : 'full');
  var states = Array.prototype.map.call(ctl.state.options, function(o){ return o.value; });
  enterState(states.indexOf(qs.get('state')) >= 0 ? qs.get('state') : 'normal', parseInt(qs.get('page'), 10) || 1);
})();
