// Static prototype only: no persistence, no real sync/settings — click handlers
// simulate the flow described in the brief so a reviewer can click through it.
(function(){
  'use strict';

  // Lengths within ~10 chars of each other (median ~76, p90 ~104 in real cards) so the
  // body always fills the max height — verdict/source live in the fixed footer instead.
  var CARD = {
    term: 'Mark price',
    tag: 'トレーディング',
    tier: '段 2',
    source: '9/20 · recordo · /btw で質問',
    options: [
      { key:'A', correct:true,  text:'無期限先物の清算判定や評価損益の計算に使う基準価格。現物価格の指数をもとに、急な値動きの影響を抑えて慎重に算出する。' },
      { key:'B', correct:false, text:'複数の主要取引所の現物価格を出来高で加重平均した参照価格。無期限先物の価格をこの水準に近づけるための基準として使う。' },
      { key:'C', correct:false, text:'無期限先物の価格を現物価格に近づけるため、買い手と売り手の間で定期的にやり取りされる手数料の割合のことを指す。' },
      { key:'D', correct:false, text:'その取引所の板で直近に約定した価格のこと。出来高が薄い時間帯は一時的に大きく値が動くことがある指標。' }
    ]
  };

  var desktop = document.getElementById('desktop');
  var stage = document.getElementById('stage');
  var menubarIcon = document.getElementById('menubar-icon');
  var ctlState = document.getElementById('ctl-state');
  var ctlTheme = document.getElementById('ctl-theme');
  var ctlText = document.getElementById('ctl-text');
  var ctlMotion = document.getElementById('ctl-motion');
  var ctlReplay = document.getElementById('ctl-replay');

  var tplQuestion = document.getElementById('tpl-question');
  var tplNotice = document.getElementById('tpl-notice');
  var tplMenu = document.getElementById('tpl-menu');
  var tplSettings = document.getElementById('tpl-settings');

  var model = { theme:'light', text:'100', motion:'full' };
  var quiz = { qIndex:1, verdict:null, pickedKey:null, discarded:false };
  var screen = 'quiz'; // 'quiz' | 'empty' | 'menu' | 'settings' | 'closed'
  var emptyKind = 'none';
  var menuKind = 'normal';

  function applyState(id){
    if(id === 'menu' || id === 'menu-syncing' || id === 'menu-failed'){
      screen = 'menu';
      menuKind = id === 'menu' ? 'normal' : id.slice(5);
      return;
    }
    if(id === 'settings'){ screen = 'settings'; return; }
    if(id === 'empty-none' || id === 'empty-due' || id === 'empty-broken'){
      screen = 'empty'; emptyKind = id.slice(6); return;
    }
    screen = 'quiz';
    quiz.discarded = false;
    switch(id){
      case 'correct':   quiz.qIndex = 1; quiz.verdict = 'correct'; quiz.pickedKey = 'A'; break;
      case 'wrong':      quiz.qIndex = 1; quiz.verdict = 'wrong';   quiz.pickedKey = 'C'; break;
      case 'idk':        quiz.qIndex = 1; quiz.verdict = 'idk';     quiz.pickedKey = null; break;
      case 'discarded':  quiz.qIndex = 1; quiz.verdict = 'wrong';   quiz.pickedKey = 'C'; quiz.discarded = true; break;
      case 'last':       quiz.qIndex = 3; quiz.verdict = 'correct'; quiz.pickedKey = 'A'; break;
      default:           quiz.qIndex = 1; quiz.verdict = null;      quiz.pickedKey = null; break; // 'question'
    }
  }

  function currentStateId(){
    if(screen === 'menu') return menuKind === 'normal' ? 'menu' : 'menu-' + menuKind;
    if(screen === 'settings') return 'settings';
    if(screen === 'empty') return 'empty-' + emptyKind;
    if(screen === 'closed') return 'question';
    if(quiz.discarded) return 'discarded';
    if(quiz.qIndex === 3 && quiz.verdict === 'correct') return 'last';
    if(!quiz.verdict) return 'question';
    return quiz.verdict;
  }

  function syncURL(){
    var p = new URLSearchParams();
    p.set('state', currentStateId());
    p.set('theme', model.theme);
    p.set('text', model.text);
    p.set('motion', model.motion);
    history.replaceState(null, '', '?' + p.toString());
  }

  function syncControls(){
    ctlState.value = currentStateId();
    ctlTheme.value = model.theme;
    ctlText.value = model.text;
    ctlMotion.value = model.motion;
  }

  function applyDesktopAttrs(){
    desktop.setAttribute('data-theme', model.theme);
    desktop.setAttribute('data-text', model.text);
    desktop.setAttribute('data-motion', model.motion);
  }

  function svgCheck(cls){
    return '<svg class="' + (cls || 'option-mark') + '" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 13l5 5L20 7"></path></svg>';
  }
  function svgCross(cls){
    return '<svg class="' + (cls || 'option-mark') + '" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"></path></svg>';
  }
  function svgWarn(){
    return '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><path d="M12 8v5"></path><circle cx="12" cy="16" r=".6" fill="currentColor" stroke="none"></circle></svg>';
  }

  // ---------- quiz body / footer builders (shared by full renders and in-place swaps) ----------

  function fillOptions(container, animateEnter){
    container.innerHTML = '';
    var answered = !!quiz.verdict;
    CARD.options.forEach(function(opt, idx){
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'option';
      var showCheck = answered && opt.correct;
      var showCross = answered && !opt.correct && quiz.pickedKey === opt.key;
      var verdictText = showCheck ? '、正解' : showCross ? '、選択した回答・不正解' : '';
      if(answered) btn.setAttribute('aria-disabled', 'true');
      if(showCheck) btn.dataset.verdict = 'correct';
      else if(showCross) btn.dataset.verdict = 'wrong';
      btn.setAttribute('aria-label', opt.key + '. ' + opt.text + verdictText);
      btn.innerHTML =
        '<span class="option-key" aria-hidden="true">' + opt.key + '</span>' +
        '<span class="option-text">' + opt.text + '</span>' +
        (showCheck ? svgCheck() : showCross ? svgCross() : '');
      if(!answered){
        btn.onclick = function(){ pickOption(opt.key); };
        // Question appears (spec #1): 30ms stagger, A→D, only on a genuine fresh mount.
        if(animateEnter){
          btn.classList.add('opt-enter');
          btn.style.animationDelay = (idx * 30) + 'ms';
        }
      }
      container.appendChild(btn);
    });
  }

  function fillQuizBody(bodyInner, animateEnter){
    bodyInner.querySelector('[data-slot=meta]').textContent = CARD.tag + ' · ' + CARD.tier;
    bodyInner.querySelector('[data-slot=term]').textContent = CARD.term;
    fillOptions(bodyInner.querySelector('[data-slot=options]'), animateEnter);
    var dontknow = bodyInner.querySelector('[data-action=idk]');
    var answered = !!quiz.verdict;
    dontknow.hidden = answered;
    dontknow.onclick = answered ? null : pickIdk;
  }

  function fillLeading(leadingHost){
    leadingHost.innerHTML = !quiz.verdict
      ? '<button type="button" class="btn-quiet" data-action="later">後で</button>'
      : quiz.discarded
        ? '<span>捨てました</span><button type="button" class="quiet-link" data-action="undo">元に戻す</button>'
        : '<button type="button" class="btn-quiet" data-action="discard">このカードを捨てる</button>';
    var later = leadingHost.querySelector('[data-action=later]'); if(later) later.onclick = closePanel;
    var disc = leadingHost.querySelector('[data-action=discard]'); if(disc) disc.onclick = discardCard;
    var undo = leadingHost.querySelector('[data-action=undo]'); if(undo) undo.onclick = undoDiscard;
  }

  // Answering (spec #3). The footer line's ~60ms lag behind the glyph lives in the CSS
  // transition-delay, not here.
  function applyAnswerReveal(panelNode, animate){
    function apply(){
      panelNode.querySelectorAll('.option[data-verdict]').forEach(function(el){
        el.classList.add(el.dataset.verdict === 'correct' ? 'is-correct' : 'is-wrong');
        var mark = el.querySelector('.option-mark');
        if(mark) mark.classList.add('pop-in');
      });
      panelNode.querySelectorAll('.option[aria-disabled=true]:not([data-verdict])').forEach(function(el){
        el.classList.add('opt-inert');
      });
      var verdictLine = panelNode.querySelector('.quiz-verdict-line');
      if(verdictLine){
        verdictLine.classList.add('reveal-in');
        var m = verdictLine.querySelector('.quiz-verdict-mark');
        if(m) m.classList.add('pop-in');
      }
    }
    if(animate){
      requestAnimationFrame(apply);
    } else {
      // Cosmetic re-render (e.g. theme toggle while answered): show the settled state, no replay.
      panelNode.classList.add('no-anim-once');
      apply();
      requestAnimationFrame(function(){ requestAnimationFrame(function(){ panelNode.classList.remove('no-anim-once'); }); });
    }
  }

  function fillQuizFooter(panelNode, animate){
    var verdictHost = panelNode.querySelector('[data-slot=verdict]');
    var leadingHost = panelNode.querySelector('[data-slot=leading]');
    var primaryBtn = panelNode.querySelector('[data-action=primary]');
    var primaryLabel = panelNode.querySelector('[data-slot=primary-label]');
    var answered = !!quiz.verdict;

    if(answered){
      var tone = quiz.verdict === 'correct' ? 'tone-success' : quiz.verdict === 'wrong' ? 'tone-bad' : 'tone-neutral';
      var mark = quiz.verdict === 'correct' ? svgCheck('quiz-verdict-mark') : quiz.verdict === 'wrong' ? svgCross('quiz-verdict-mark') : '';
      var correctOpt = CARD.options.filter(function(o){ return o.correct; })[0];
      var title = quiz.verdict === 'correct' ? '正解' : quiz.verdict === 'wrong' ? '不正解' : ('正しい答えは ' + correctOpt.key);
      verdictHost.hidden = false;
      verdictHost.innerHTML =
        '<p class="quiz-verdict-line">' +
          '<span class="quiz-verdict-title ' + tone + '">' + mark + title + '</span>' +
          '<span class="quiz-verdict-source">' + CARD.source + '</span>' +
        '</p>';
      fillLeading(leadingHost);

      var isLast = quiz.qIndex >= 3;
      primaryBtn.hidden = false;
      primaryLabel.textContent = isLast ? '閉じる' : '次へ';
      primaryBtn.onclick = function(){ primaryAction(isLast); };

      applyAnswerReveal(panelNode, animate);

      var correctBtn = panelNode.querySelector('[data-verdict=correct]');
      if(correctBtn){
        requestAnimationFrame(function(){
          correctBtn.scrollIntoView({ block:'nearest', behavior: model.motion === 'reduce' ? 'auto' : 'smooth' });
        });
      }
    } else {
      verdictHost.hidden = true;
      verdictHost.innerHTML = '';
      fillLeading(leadingHost);
      primaryBtn.hidden = true;
      primaryBtn.onclick = null;
    }
  }

  // ---------- full-panel rendering ----------

  function renderQuiz(animate){
    stage.innerHTML = '';
    var node = tplQuestion.content.firstElementChild.cloneNode(true);
    node.querySelector('[data-slot=counter]').textContent = '復習 ' + quiz.qIndex + '/3';
    fillQuizBody(node.querySelector('[data-slot=body-inner]'), !!animate);
    fillQuizFooter(node, !!animate);
    node.querySelector('[data-action=close]').onclick = closePanel;

    stage.appendChild(node);
    node.classList.add(animate === 'swap' ? 'motion-swap' : 'motion-enter');
  }

  function renderNotice(){
    stage.innerHTML = '';
    var node = tplNotice.content.firstElementChild.cloneNode(true);
    var copy = {
      none:   { title:'まだカードがありません', body:'Claude Code で用語の意味を聞くと、次の同期でカードになります。',
                actions:[{ label:'閉じる', primary:false },{ label:'同期', primary:true }] },
      due:    { title:'今出せるカードはありません', body:'次は今日 21:40 に 2 枚出ます。',
                actions:[{ label:'閉じる', primary:true }] },
      broken: { title:'cards.json を読めませんでした', body:'ファイルを直すまで、取り込みと出題を止めています。',
                actions:[{ label:'Finder で表示', primary:false },{ label:'閉じる', primary:true }] }
    }[emptyKind];
    node.querySelector('[data-slot=title]').textContent = copy.title;
    node.querySelector('[data-slot=body]').textContent = copy.body;
    var actionsHost = node.querySelector('[data-slot=actions]');
    if(copy.actions.length === 1) actionsHost.style.justifyContent = 'flex-end';
    copy.actions.forEach(function(a){
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = a.primary ? 'btn-primary' : 'btn-quiet';
      btn.textContent = a.label;
      // Prototype only: every action here just closes the panel, real commands are native.
      btn.onclick = closePanel;
      actionsHost.appendChild(btn);
    });
    node.querySelector('[data-action=close]').onclick = closePanel;
    stage.appendChild(node);
    node.classList.add('motion-enter');
  }

  function menuRow(label, opts){
    opts = opts || {};
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'menu-row' + (opts.warn ? ' warn' : '');
    btn.setAttribute('role', 'menuitem');
    var inner = '';
    if(opts.spinner) inner += '<span class="menu-spinner" aria-hidden="true"></span>';
    if(opts.warn) inner += svgWarn();
    inner += '<span class="menu-label">' + label + '</span>';
    if(opts.trailing) inner += '<span class="menu-trailing">' + opts.trailing + '</span>';
    if(opts.key) inner += '<span class="menu-key">' + opts.key + '</span>';
    btn.innerHTML = inner;
    if(opts.disabled){ btn.disabled = true; btn.setAttribute('aria-disabled', 'true'); }
    if(opts.onClick) btn.onclick = opts.onClick;
    return btn;
  }

  function renderMenu(){
    stage.innerHTML = '';
    var node = tplMenu.content.firstElementChild.cloneNode(true);

    node.appendChild(menuRow('出題', { onClick:function(){ screen = 'quiz'; applyState('question'); render(true); } }));
    if(menuKind === 'syncing'){
      node.appendChild(menuRow('同期中 3/11', { disabled:true, spinner:true }));
    } else {
      node.appendChild(menuRow('同期', { onClick:function(){ menuKind = 'syncing'; render(true); } }));
    }
    if(menuKind === 'failed'){
      node.appendChild(menuRow('同期できませんでした：claude にログインしてください', { warn:true, disabled:true }));
    }
    node.appendChild(Object.assign(document.createElement('div'), { className:'menu-separator' }));
    node.appendChild(menuRow('最後の同期：今日 19:04', { disabled:true }));
    node.appendChild(Object.assign(document.createElement('div'), { className:'menu-separator' }));
    node.appendChild(menuRow('設定…', { key:'⌘,', onClick:function(){ screen = 'settings'; render(true); } }));
    node.appendChild(menuRow('Recordo を終了', { key:'⌘Q', onClick:closePanel }));

    stage.appendChild(node);
    node.classList.add('motion-enter');
  }

  function renderSettings(){
    stage.innerHTML = '';
    var node = tplSettings.content.firstElementChild.cloneNode(true);
    stage.appendChild(node);
    node.classList.add('motion-enter');

    // Toggle (spec #8): flips aria-checked, the knob/track CSS transition handles the motion,
    // and the two time fields fade to disabled while quiet hours are off.
    var switchBtn = node.querySelector('.switch');
    var fields = node.querySelectorAll('.time-field');
    switchBtn.onclick = function(){
      var on = switchBtn.getAttribute('aria-checked') !== 'true';
      switchBtn.setAttribute('aria-checked', String(on));
      fields.forEach(function(f){ f.disabled = !on; });
    };
  }

  var debugSlow = false; // verification-only, set from the URL at init

  function render(animate){
    applyDesktopAttrs();
    menubarIcon.setAttribute('aria-expanded', screen === 'menu' ? 'true' : 'false');
    if(screen === 'quiz') renderQuiz(animate);
    else if(screen === 'empty') renderNotice();
    else if(screen === 'menu') renderMenu();
    else if(screen === 'settings') renderSettings();
    else stage.innerHTML = '';
    syncControls();
    syncURL();
    // Verification only: inline !important beats any stylesheet cascade ambiguity, so the
    // slow-motion override is guaranteed to apply to every animation/transition in the node.
    if(debugSlow){
      stage.querySelectorAll('*').forEach(function(el){
        el.style.setProperty('animation-duration', '2s', 'important');
        el.style.setProperty('animation-delay', '0s', 'important');
        el.style.setProperty('transition-duration', '2s', 'important');
        el.style.setProperty('transition-delay', '0s', 'important');
      });
    }
  }

  // ---------- interactions ----------

  // Answering updates the open panel in place; a full render would replay the panel entrance.
  function revealAnswer(){
    var panelNode = stage.firstElementChild;
    if(screen !== 'quiz' || !panelNode){ render(true); return; }
    fillQuizBody(panelNode.querySelector('[data-slot=body-inner]'), false);
    fillQuizFooter(panelNode, true);
    syncControls();
    syncURL();
  }
  function pickOption(key){
    quiz.verdict = key === 'A' ? 'correct' : 'wrong';
    quiz.pickedKey = key;
    quiz.discarded = false;
    revealAnswer();
    celebrateIfLast();
  }
  // Once, on answering the last question, whatever the result: a completion mark, not a score.
  function celebrateIfLast(){
    var panel = stage.querySelector('.quiz-panel');
    if(!panel || model.motion === 'reduce' || quiz.qIndex < 3 || !quiz.verdict) return;
    var layer = document.createElement('div');
    layer.className = 'confetti-layer';
    layer.setAttribute('aria-hidden', 'true');
    panel.appendChild(layer);
    var colors = ['var(--secondary)', 'var(--success)', 'var(--tertiary)'];
    var height = panel.clientHeight;
    for(var i = 0; i < 28; i++){
      var piece = document.createElement('i');
      piece.className = 'confetti-piece';
      piece.style.left = (Math.random() * 100) + '%';
      piece.style.background = colors[i % colors.length];
      layer.appendChild(piece);
      var spin = (Math.random() * 1080 - 540);
      piece.animate([
        { transform:'translate(-50%, -24px) rotate(0deg)', opacity:1 },
        { transform:'translate(-50%, ' + (height + 24) + 'px) rotate(' + spin + 'deg)', opacity:0 }
      ], { duration:1800, delay:Math.random() * 400, easing:'ease-in', fill:'both' });
    }
    setTimeout(function(){ layer.remove(); }, 2200);
  }
  function pickIdk(){
    quiz.verdict = 'idk';
    quiz.pickedKey = null;
    quiz.discarded = false;
    revealAnswer();
    celebrateIfLast();
  }

  // Discard/undo (spec #6): the leading control crossfades in place, ~150ms total.
  function crossfadeLeading(){
    var leadingHost = stage.querySelector('[data-slot=leading]');
    if(!leadingHost) return;
    var half = model.motion === 'reduce' ? 60 : 75;
    leadingHost.style.transition = 'opacity ' + half + 'ms ease';
    leadingHost.style.opacity = '0';
    setTimeout(function(){
      fillLeading(leadingHost);
      requestAnimationFrame(function(){ leadingHost.style.opacity = '1'; });
    }, half);
  }
  function discardCard(){
    quiz.discarded = true;
    crossfadeLeading();
    syncURL(); syncControls();
  }
  function undoDiscard(){
    quiz.discarded = false;
    crossfadeLeading();
    syncURL(); syncControls();
  }

  // Next question (spec #4): slide the current body out left, refill it in place, slide the
  // new one in from the right. Falls back to a full opacity-crossfade render under reduced motion.
  function advanceQuestion(){
    quiz.qIndex += 1;
    quiz.verdict = null;
    quiz.pickedKey = null;
    quiz.discarded = false;
    screen = 'quiz';

    var panel = stage.querySelector('.quiz-panel');
    var bodyInner = panel && panel.querySelector('[data-slot=body-inner]');
    var counterEl = panel && panel.querySelector('[data-slot=counter]');

    if(!panel || !bodyInner || model.motion === 'reduce'){ render('swap'); return; }

    counterEl.classList.add('counter-fade');
    bodyInner.classList.remove('body-enter');
    bodyInner.classList.add('body-exit');
    bodyInner.addEventListener('animationend', function onExit(){
      bodyInner.removeEventListener('animationend', onExit);
      fillQuizBody(bodyInner, false);
      fillQuizFooter(panel, false);
      counterEl.textContent = '復習 ' + quiz.qIndex + '/3';
      counterEl.classList.remove('counter-fade');
      bodyInner.classList.remove('body-exit');
      void bodyInner.offsetWidth; // restart the enter keyframe on the same element
      bodyInner.classList.add('body-enter');
    }, { once:true });

    syncURL(); syncControls();
  }

  function primaryAction(isLast){
    if(isLast){ closePanel(); return; }
    advanceQuestion();
  }

  // Close (spec #5): the current panel exits the way it entered, then the state clears.
  // Menu gets its own exit (spec #7) via the .menu-dropdown CSS override on the same class.
  function exitPanelThen(cb){
    var node = stage.firstElementChild;
    if(!node){ cb(); return; }
    var done = false;
    function finish(){ if(done) return; done = true; node.removeEventListener('animationend', finish); cb(); }
    node.classList.remove('motion-enter');
    node.classList.add('motion-exit');
    node.addEventListener('animationend', finish);
    setTimeout(finish, 260); // safety net if a node type has no matching exit rule
  }
  function closePanel(){
    exitPanelThen(function(){ screen = 'closed'; render(false); });
  }

  menubarIcon.onclick = function(){
    if(screen === 'menu'){ closePanel(); return; }
    screen = 'menu';
    menuKind = 'normal';
    render(true);
  };

  ctlState.addEventListener('change', function(){ applyState(ctlState.value); render(true); });
  ctlTheme.addEventListener('change', function(){ model.theme = ctlTheme.value; render(false); });
  ctlText.addEventListener('change', function(){ model.text = ctlText.value; render(false); });
  ctlMotion.addEventListener('change', function(){ model.motion = ctlMotion.value; render(false); });
  ctlReplay.addEventListener('click', function(){ render(true); celebrateIfLast(); });

  document.addEventListener('keydown', function(e){
    if(e.repeat || e.metaKey || e.ctrlKey || e.altKey) return;
    var tag = (e.target && e.target.tagName) || '';
    if(tag === 'INPUT' || tag === 'SELECT' || tag === 'TEXTAREA') return;
    if(screen !== 'quiz') return;
    var k = e.key.toLowerCase();
    if(!quiz.verdict){
      var map = { a:'A', '1':'A', b:'B', '2':'B', c:'C', '3':'C', d:'D', '4':'D' };
      if(map[k]){ pickOption(map[k]); return; }
    }
    if(e.key === ' '){
      if(tag === 'BUTTON') return; // a focused button already activates on Space natively
      e.preventDefault();
      var primary = stage.querySelector('[data-action=primary]');
      if(primary && !primary.hidden) primary.click();
    }
  });

  // ---------- init from URL ----------
  var qs = new URLSearchParams(location.search);
  model.theme = qs.get('theme') === 'dark' ? 'dark' : 'light';
  model.text = qs.get('text') === '200' ? '200' : '100';
  // The toolbar is authoritative: OS prefers-reduced-motion only seeds the default when the
  // URL doesn't already say otherwise; picking Full afterwards is never overridden by the OS.
  var motionParam = qs.get('motion');
  if(motionParam === 'reduce' || motionParam === 'full'){
    model.motion = motionParam;
  } else {
    model.motion = (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) ? 'reduce' : 'full';
  }
  // Verification only, not shipped: stretches every animation to 2s (see render()) so a
  // plain screenshot reliably lands mid-flight.
  debugSlow = qs.get('debug') === 'slow';

  applyState(qs.get('state') || 'question');
  render(true);
  celebrateIfLast();
})();
