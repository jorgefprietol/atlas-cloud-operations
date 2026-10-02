import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { UserManager, WebStorageStateStore } from 'oidc-client-ts';
import { Layers3, LayoutDashboard, ListChecks, ShieldCheck, Activity, ArrowUpRight, Plus, Search, X, Check, Clock3, AlertTriangle, LogOut, LockKeyhole, RefreshCw, ChevronRight, FileJson, Globe2 } from 'lucide-react';
import { kinds, statuses, summarize, type Operation, type Audit } from './domain';
import './styles.css';

interface Config { mode: string; authority: string; clientId: string; redirectUri: string }
const date = (v: string) => new Intl.DateTimeFormat('es', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }).format(new Date(v));

function App() {
  const [config, setConfig] = useState<Config>();
  const [manager, setManager] = useState<UserManager>();
  const [token, setToken] = useState('');
  const [draftToken, setDraftToken] = useState('');
  const [items, setItems] = useState<Operation[]>([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [section, setSection] = useState('overview');
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState('all');
  const [showForm, setShowForm] = useState(false);
  const [formKey, setFormKey] = useState('');
  const [selected, setSelected] = useState<Operation>();
  const [audit, setAudit] = useState<Audit[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [notice, setNotice] = useState('');
  const [lastUpdated, setLastUpdated] = useState<string>();
  useEffect(() => {
    fetch('/config.json').then(r => { if (!r.ok) throw new Error('No se pudo cargar la configuración'); return r.json(); }).then(async (c: Config) => {
      setConfig(c);
      if (c.mode !== 'development') {
        const auth = new UserManager({ authority: c.authority, client_id: c.clientId, redirect_uri: c.redirectUri,
          response_type: 'code', scope: 'openid atlas/operate', userStore: new WebStorageStateStore({ store: window.sessionStorage }),
          loadUserInfo: false, automaticSilentRenew: false });
        setManager(auth);
        auth.events.addAccessTokenExpired(() => { setToken(''); setItems([]); setSelected(undefined); });
        if (location.pathname === '/auth/callback') {
          const user = await auth.signinRedirectCallback(); setToken(user.access_token); history.replaceState({}, '', '/');
        } else { const user = await auth.getUser(); if (user && !user.expired) setToken(user.access_token); }
      }
    }).catch(e => setError(e.message));
  }, []);
  async function api(path: string, options?: RequestInit) {
    const r = await fetch('/api' + path, { ...options, headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token, ...options?.headers } });
    if (r.status === 401) { setToken(''); setItems([]); setSelected(undefined); throw new Error('La sesión expiró o la credencial es incorrecta.'); }
    if (!r.ok) throw new Error(r.status === 409 ? 'La solicitud ya existe con datos diferentes.' : 'No se pudo completar la operación. Revisa los datos y la conexión.');
    return r.json();
  }
  async function refresh() {
    if (!token) return;
    setLoading(true);
    try { const data = await api('/requests'); setItems(data); setError(''); setLastUpdated(new Date().toISOString()); }
    catch (e) { setError((e as Error).message); } finally { setLoading(false); }
  }
  useEffect(() => { void refresh(); if (!token) return; const interval = setInterval(() => void refresh(), 5000); return () => clearInterval(interval); }, [token]);
  useEffect(() => { if (showForm) setFormKey(crypto.randomUUID()); }, [showForm]);
  useEffect(() => {
    if (!selected) return;
    const current = items.find(item => item.id === selected.id);
    if (current && current.status !== selected.status) {
      setSelected(current);
      api(`/requests/${current.id}/audit`).then(setAudit).catch(e => setError(e.message));
    }
  }, [items]);
  async function detail(item: Operation) { setSelected(item); setAudit([]); try { setAudit(await api(`/requests/${item.id}/audit`)); } catch (e) { setError((e as Error).message); } }
  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault(); const form = new FormData(e.currentTarget); setSubmitting(true);
    try {
      await api('/requests', { method: 'POST', headers: { 'Idempotency-Key': formKey }, body: JSON.stringify({
        title: form.get('title'), kind: form.get('kind'), region: form.get('region'), classification: form.get('classification'), retentionDays: Number(form.get('retentionDays')) }) });
      setShowForm(false); setNotice('Solicitud registrada. La evaluación se procesará automáticamente.'); await refresh();
    } catch (e) { setError((e as Error).message); } finally { setSubmitting(false); }
  }
  const stats = summarize(items);
  const visible = items.filter(x => (filter === 'all' || x.status === filter) && `${x.title} ${x.region} ${kinds[x.kind]}`.toLowerCase().includes(search.toLowerCase()));
  const nav = [{ id: 'overview', label: 'Vista general', icon: LayoutDashboard }, { id: 'operations', label: 'Operaciones', icon: ListChecks }, { id: 'policies', label: 'Políticas', icon: ShieldCheck }];
  return <div className="app-shell">
    <aside className="sidebar"><a href="/" className="brand"><span className="brand-mark"><Layers3 size={23}/></span><span>atlas<span className="brand-sub">CLOUD OPERATIONS</span></span></a>
      <div className="workspace"><span className="workspace-symbol">A</span><div>Operations workspace<small>Centro de control</small></div><ChevronRight size={15}/></div>
      <p className="nav-caption">WORKSPACE</p><nav>{nav.map(n => <button key={n.id} className={section === n.id ? 'active' : ''} onClick={() => setSection(n.id)}><n.icon size={18}/>{n.label}{n.id === 'operations' && <span className="nav-count">{stats.total}</span>}</button>)}</nav>
      <div className="sidebar-bottom"><div className="security-note"><ShieldCheck size={19}/><strong>Trazabilidad por diseño</strong><p>Cada decisión conserva su historial y evidencia.</p></div><div className="profile"><div className="avatar">OP</div><div>Operador<small>{token ? 'Sesión activa' : 'Sin conexión'}</small></div>{token && <button aria-label="Cerrar sesión" onClick={async () => { setToken(''); setItems([]); setSelected(undefined); await manager?.removeUser(); }}><LogOut size={17}/></button>}</div></div>
    </aside>
    <div className="main-shell"><header className="topbar"><div className="breadcrumb">Workspace <ChevronRight size={14}/><strong>{nav.find(n => n.id === section)?.label}</strong></div><div className="topbar-right"><span className="environment"><span/>{config?.mode === 'development' ? 'Entorno local' : 'AWS workspace'}</span><span className="topbar-divider"/><span className="avatar small">OP</span></div></header>
      <main><div className="page-heading"><div><div className="eyebrow">CONTROL · VISIBILIDAD · EVIDENCIA</div><h1>{section === 'policies' ? 'Políticas de operación' : section === 'operations' ? 'Registro de operaciones' : 'Tu operación, en perspectiva.'}</h1><p>Gestiona solicitudes cloud con decisiones verificables y un historial completo.</p></div><button className="primary" disabled={!token} onClick={() => { setError(''); setShowForm(true); }}><Plus size={17}/> Nueva solicitud</button></div>
      {error && <div className="alert error" role="alert"><AlertTriangle size={18}/>{error}<button aria-label="Cerrar alerta" onClick={() => setError('')}><X size={16}/></button></div>}
      {notice && <div className="alert success" role="status"><Check size={18}/>{notice}<button aria-label="Cerrar notificación" onClick={() => setNotice('')}><X size={16}/></button></div>}
      {!token && <section className="connection"><div className="connection-icon"><LockKeyhole/></div><div><h2>Conecta tu espacio de trabajo</h2><p>{config?.mode === 'development' ? 'Usa la credencial local generada en .env para consultar y registrar solicitudes.' : 'Accede con tu identidad corporativa para consultar tus operaciones.'}</p></div>{config?.mode === 'development' ? <form onSubmit={e => { e.preventDefault(); setToken(draftToken.trim()); setDraftToken(''); }}><input aria-label="Credencial local" type="password" required value={draftToken} onChange={e => setDraftToken(e.target.value)} placeholder="Credencial local"/><button className="primary">Conectar <ArrowUpRight size={16}/></button></form> : <button className="primary" disabled={!manager} onClick={() => void manager?.signinRedirect()}>Iniciar sesión <ArrowUpRight size={16}/></button>}</section>}
      {section === 'policies' ? <section className="policy-grid">{[
        ['Residencia de datos','La información confidencial se valida exclusivamente en us-east-1.','Región primaria'],
        ['Retención de respaldos','Los respaldos requieren una retención mínima de 30 días.','30–3650 días'],
        ['Exportación controlada','Las exportaciones confidenciales se rechazan hasta obtener aprobación independiente.','Revisión requerida'],
        ['Evidencia y auditoría','Cada evaluación registra una decisión, su explicación y un informe JSON.','Trazabilidad completa']
      ].map(([title, text, tag]) => <article className="policy-card" key={title}><ShieldCheck size={25}/><h2>{title}</h2><p>{text}</p><span>{tag}</span></article>)}</section> : <>
      <div className="stat-grid">{[
        {label:'Solicitudes registradas',value:stats.total,icon:Layers3,tone:'blue',sub:'Últimas 100 de tu cuenta'},
        {label:'Operaciones validadas',value:stats.validated,icon:ShieldCheck,tone:'green',sub:'Cumplen las políticas'},
        {label:'Pendientes de evaluación',value:stats.queued,icon:Clock3,tone:'amber',sub:'Procesamiento asíncrono'},
        {label:'Requieren atención',value:stats.rejected,icon:AlertTriangle,tone:'rose',sub:'Decisión disponible en el detalle'}
      ].map(s => <article className="stat-card" key={s.label}><div className="stat-top"><span>{s.label}</span><span className={`stat-icon ${s.tone}`}><s.icon size={18}/></span></div><strong>{s.value.toString().padStart(2,'0')}</strong><small>{s.sub}</small></article>)}</div>
      {section === 'overview' && <section className="overview-strip"><div><span className="strip-icon"><Activity size={20}/></span><div><strong>Una ruta clara, desde la solicitud hasta la evidencia</strong><p>Las políticas evalúan residencia, retención y manejo de datos.</p></div></div><button onClick={() => setSection('policies')}>Ver políticas <ArrowUpRight size={16}/></button></section>}
      <section className="operations-panel"><div className="panel-heading"><div><h2>Actividad operativa <span>{stats.total}</span></h2><p>Solicitudes recientes y su estado de evaluación.</p></div><button className="refresh" onClick={() => void refresh()} disabled={!token || loading}><RefreshCw size={15} className={loading ? 'spin' : ''}/> Actualizar</button></div>
      <div className="table-toolbar"><div className="tabs">{[['all','Todas'],['queued','En evaluación'],['validated','Validadas'],['rejected','Rechazadas']].map(([value,label]) => <button key={value} className={filter === value ? 'selected' : ''} onClick={() => setFilter(value)}>{label}</button>)}</div><label className="search"><Search size={16}/><input aria-label="Buscar solicitudes" placeholder="Buscar solicitudes…" value={search} onChange={e => setSearch(e.target.value)}/></label></div>
      <div className="table-scroll"><table><thead><tr><th>SOLICITUD</th><th>REGIÓN</th><th>CLASIFICACIÓN</th><th>ESTADO</th><th>REGISTRADA</th><th/></tr></thead><tbody>{visible.map(item => <tr key={item.id}><td><button className="request-title" onClick={() => void detail(item)}>{item.title}</button><small>{kinds[item.kind]} · {item.id.slice(0,8)}</small></td><td><span className="region"><Globe2 size={13}/>{item.region}</span></td><td><span className="classification">{item.classification === 'confidential' ? 'Confidencial' : 'Interna'}</span></td><td><span className={`badge ${item.status}`}><span/>{statuses[item.status]}</span></td><td className="date">{date(item.createdAt)}</td><td><button aria-label={`Ver ${item.title}`} className="detail-button" onClick={() => void detail(item)}><ChevronRight size={18}/></button></td></tr>)}</tbody></table></div>
      {visible.length === 0 && <div className="empty-state"><ListChecks size={32}/><h3>{search || filter !== 'all' ? 'No hay resultados para este filtro' : 'Todo comienza con una solicitud'}</h3><p>{search || filter !== 'all' ? 'Prueba otra búsqueda o consulta todos los estados.' : 'Registra una operación para evaluar sus políticas y conservar la evidencia.'}</p>{token && !search && filter === 'all' && <button className="text-button" onClick={() => setShowForm(true)}>Crear la primera solicitud <ArrowUpRight size={15}/></button>}</div>}
      <div className="panel-footer"><span><span className={`status-dot ${token && !error ? 'online' : ''}`}/>{token && !error ? 'Consulta activa · Actualización cada 5 s' : 'Conecta tu cuenta para consultar actividad'}</span><span>{lastUpdated ? 'Última consulta: ' + date(lastUpdated) : 'Sin datos de actividad'}</span></div></section>
      </>}
      <footer className="page-footer"><span>ATLAS / CLOUD OPERATIONS</span><span>Decisiones claras. Operaciones trazables.</span></footer></main>
    </div>
    {showForm && <div className="modal-backdrop"><section className="modal" role="dialog" aria-modal="true" aria-labelledby="new-title"><div className="modal-heading"><div><span className="eyebrow">OPERACIÓN CLOUD</span><h2 id="new-title">Nueva solicitud</h2></div><button aria-label="Cerrar formulario" onClick={() => setShowForm(false)}><X size={21}/></button></div><p>Define la operación. El motor de políticas evaluará la solicitud y registrará la decisión.</p><form onSubmit={submit}><label>Nombre de la solicitud<input name="title" required maxLength={120} placeholder="Ej. Respaldo mensual de auditoría"/></label><div className="form-grid"><label>Tipo de operación<select name="kind">{Object.entries(kinds).map(([k,v]) => <option key={k} value={k}>{v}</option>)}</select></label><label>Región<select name="region"><option>us-east-1</option><option>us-west-2</option><option>eu-west-1</option></select></label><label>Clasificación<select name="classification"><option value="internal">Interna</option><option value="confidential">Confidencial</option></select></label><label>Retención (días)<input name="retentionDays" type="number" min={1} max={3650} defaultValue={90} required/></label></div><div className="form-note"><ShieldCheck size={17}/>Las solicitudes se validan según las políticas vigentes.</div><div className="modal-actions"><button type="button" className="secondary" onClick={() => setShowForm(false)}>Cancelar</button><button className="primary" disabled={submitting}>{submitting ? 'Registrando…' : 'Registrar solicitud'}<ArrowUpRight size={16}/></button></div></form></section></div>}
    {selected && <div className="modal-backdrop"><section className="modal" role="dialog" aria-modal="true" aria-labelledby="detail-title"><div className="modal-heading"><div><span className="eyebrow">DETALLE DE OPERACIÓN</span><h2 id="detail-title">{selected.title}</h2></div><button aria-label="Cerrar detalle" onClick={() => setSelected(undefined)}><X size={21}/></button></div><span className={`badge ${selected.status}`}><span/>{statuses[selected.status]}</span><p>{selected.decision ?? 'La solicitud está en la cola de evaluación.'}</p><div className="detail-grid"><div><small>TIPO</small><strong>{kinds[selected.kind]}</strong></div><div><small>REGIÓN</small><strong>{selected.region}</strong></div><div><small>RETENCIÓN</small><strong>{selected.retentionDays} días</strong></div><div><small>CLASIFICACIÓN</small><strong>{selected.classification === 'confidential' ? 'Confidencial' : 'Interna'}</strong></div></div><h3>Historial de auditoría</h3><div className="timeline">{audit.map((a,i) => <div key={i}><span className="timeline-dot"/><strong>{a.action === 'requested' ? 'Solicitud registrada' : statuses[a.action as keyof typeof statuses] ?? a.action}</strong><small>{date(a.createdAt)}</small><p>{a.detail}</p></div>)}</div>{selected.reportKey && <div className="report"><FileJson size={19}/><div><strong>Informe de evaluación</strong><code>{selected.reportKey}</code><small>Disponible para operadores autorizados en el almacén de evidencia.</small></div></div>}</section></div>}
  </div>;
}
createRoot(document.getElementById('root')!).render(<App/>);
