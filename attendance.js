// Session-level attendance is the single source for attendance summaries.
// Draft marks autosave locally. Finalized meetings feed reporting percentages.
const ATTENDANCE_KEY = 'maxis-impact-attendance-v1';
const attendanceStore = loadAttendanceStore();
let selectedMeetingId = '';

function loadAttendanceStore() {
  const empty = () => ({ months: [...months], sessions: [] });
  try {
    const saved = JSON.parse(localStorage.getItem(ATTENDANCE_KEY) || 'null');
    if (!saved || !Array.isArray(saved.sessions) || saved.sessions.length > 1000 ||
        !Array.isArray(saved.months) || saved.months.length > 120 ||
        !months.every((m,i)=>saved.months[i]===m) ||
        new Set(saved.months).size!==saved.months.length || !saved.months.every(m=>/^(January|February|March|April|May|June|July|August|September|October|November|December) \d{4}$/.test(m))) return empty();
    const ids = new Set(), keys = new Set();
    const valid = saved.sessions.every(s=>{
      const key=s.programme+'|'+s.cohort+'|'+s.number;
      if (!s || typeof s.id!=='string' || ids.has(s.id) || keys.has(key) ||
          !['Accelerator','Digital Marketing'].includes(s.programme) || !['01','02'].includes(s.cohort) ||
          !Number.isInteger(s.number) || s.number<1 || s.number>999 || !validSessionDate(s.date) ||
          typeof s.title!=='string' || !['draft','finalized'].includes(s.status) ||
          !Array.isArray(s.roster) || new Set(s.roster).size!==s.roster.length ||
          !s.roster.every(id=>/^EKU-\d{3,}$/.test(id)) || !s.marks || typeof s.marks!=='object' ||
          !s.roster.every(id=>['present','absent','unmarked'].includes(s.marks[id])) ||
          (s.status==='finalized' && s.roster.some(id=>s.marks[id]==='unmarked'))) return false;
      ids.add(s.id);keys.add(key);return true;
    });
    if(!valid)return empty();
    months.splice(0,months.length,...saved.months);
    return saved;
  } catch { return empty(); }
}

function validSessionDate(value) {
  if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value))return false;
  const d=new Date(value+'T12:00:00Z');return !Number.isNaN(d.getTime())&&d.toISOString().slice(0,10)===value;
}
function sessionDateToday() {
  const parts=new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Kuala_Lumpur',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date());
  const get=t=>parts.find(p=>p.type===t).value;return `${get('year')}-${get('month')}-${get('day')}`;
}
function periodLabel(date) {return new Date(date+'T12:00:00Z').toLocaleDateString('en-GB',{month:'long',year:'numeric',timeZone:'UTC'});}
function initializeAttendance() {
  for(const p of people){while(p.monthly.length<months.length)p.monthly.push(null);while(p.attendance.length<months.length)p.attendance.push(0);}
  $('#month').innerHTML=months.map((m,i)=>`<option value="${i}" ${i===2?'selected':''}>${esc(m)}</option>`).join('');
}
function saveAttendance() {
  try {attendanceStore.months=[...months];localStorage.setItem(ATTENDANCE_KEY,JSON.stringify(attendanceStore));return true;}
  catch {notify('Attendance could not be saved locally. These changes will last only until reload.');return false;}
}
function ensureReportingMonth(date) {
  const label=periodLabel(date);let i=months.indexOf(label);
  if(i<0){months.push(label);i=months.length-1;for(const p of people){p.monthly.push(null);p.attendance.push(0);}saveLocal();}
  $('#month').innerHTML=months.map((m,index)=>`<option value="${index}">${esc(m)}</option>`).join('');
  return i;
}
function meetingScope() {return attendanceStore.sessions.filter(s=>s.programme===state.programme&&s.cohort===state.cohort).sort((a,b)=>a.number-b.number);}
function sessionParticipants(s) {return s.roster.map(id=>people.find(p=>p.id===id)).filter(Boolean);}
function sessionCounts(s) {const roster=sessionParticipants(s);return {total:roster.length,present:roster.filter(p=>s.marks[p.id]==='present').length,absent:roster.filter(p=>s.marks[p.id]==='absent').length,unmarked:roster.filter(p=>s.marks[p.id]==='unmarked').length};}
function reportingCutoff(m) {
  const [name,year]=months[m].split(' ');
  const index=['January','February','March','April','May','June','July','August','September','October','November','December'].indexOf(name);
  return new Date(Date.UTC(Number(year),index+1,0)).toISOString().slice(0,10);
}
function participantAttendance(p,m=null) {
  const cutoff=m===null?'9999-12-31':reportingCutoff(m);
  const sessions=attendanceStore.sessions.filter(s=>s.status==='finalized'&&s.date<=cutoff&&s.roster.includes(p.id));
  return {present:sessions.filter(s=>s.marks[p.id]==='present').length,total:sessions.length,absent:sessions.filter(s=>s.marks[p.id]==='absent').length};
}
function attendanceTotals(ps,m) {
  return ps.reduce((tot,p)=>{const a=participantAttendance(p,m);tot.present+=a.present;tot.total+=a.total;return tot;},{present:0,total:0});
}
function attendanceMonthNote(m) {
  return attendanceStore.sessions.filter(s=>s.status==='finalized'&&s.date<=reportingCutoff(m)&&scope().some(p=>s.roster.includes(p.id))).length;
}

function attendancePage() {
  if(state.programme==='all'||state.cohort==='all')return `<section class="card attendance-welcome"><span class="tag">SESSION REGISTER</span><h2>Take attendance for a meeting</h2><p>Select one programme and one cohort above to load the session register.</p><div class="attendance-steps"><div><b>1</b><span>Select programme & cohort</span></div><div><b>2</b><span>Choose a meeting number</span></div><div><b>3</b><span>Mark each participant’s attendance</span></div></div><p class="note">The register covers everyone in the selected programme and cohort. Stakeholders can view the register; mentors can record attendance.</p></section>`;
  const sessions=meetingScope();let s=sessions.find(s=>s.id===selectedMeetingId);if(!s)selectedMeetingId='';
  if(s&&s.status==='draft'&&!s.rosterFrozen&&state.role==='mentor'){
    const newPeople=people.filter(p=>p.programme===s.programme&&p.cohort===s.cohort&&!s.roster.includes(p.id));
    if(newPeople.length){for(const p of newPeople){s.roster.push(p.id);s.marks[p.id]='unmarked';}saveAttendance();}
  }
  const eligible=people.filter(p=>p.programme===state.programme&&p.cohort===state.cohort).length;
  return `<section class="card card-pad meeting-picker"><div><h2>Session attendance register</h2><p>eKU ${esc(state.programme)} · Cohort ${esc(state.cohort)} · ${eligible} current participants</p></div><div class="meeting-controls"><label>Meeting number<select id="meeting-select"><option value="">Select a meeting</option>${sessions.map(t=>`<option value="${esc(t.id)}" ${t.id===selectedMeetingId?'selected':''}>Meeting ${t.number} · ${t.date} · ${t.status==='finalized'?'Finalized':'Live draft'}</option>`).join('')}</select></label>${state.role==='mentor'?'<button class="primary" id="new-meeting">Create meeting</button>':''}</div></section>${s?renderMeeting(s):`<section class="card empty"><h3>${sessions.length?'Choose a meeting to view its register.':'No meetings have been created for this programme and cohort.'}</h3><p>${state.role==='mentor'?'Create a meeting, choose its number and date, then mark participants one by one.':'A mentor can create a meeting and record attendance.'}</p></section>`}`;
}
function renderMeeting(s) {
  const k=sessionCounts(s),editable=state.role==='mentor'&&s.status==='draft';
  return `<div class="stats attendance-stats">${stat('Participants on register',k.total,'Whole session roster')}${stat('Present',k.present,`${pct(k.present,k.total)}% of session roster`)}${stat('Absent',k.absent,'Explicitly marked absent')}${stat('Not marked yet',k.unmarked,k.unmarked?'Mark these before finalizing':'Register complete')}</div><section class="card"><div class="table-head"><div><h2>Meeting ${s.number}${s.title?' · '+esc(s.title):''}</h2><p>${s.date} · <span class="tag ${s.status==='draft'?'amber':''}">${s.status==='draft'?'Live draft':'Finalized'}</span></p></div><div class="register-actions">${editable?'<span class="autosave-label">Changes save automatically in this browser</span>':''}${state.role==='mentor'?s.status==='draft'?`<button class="primary" id="finalize-meeting" ${k.unmarked?'disabled title="Mark every participant before finalizing"':''}>Finalize attendance</button>`:'<button class="secondary" id="reopen-meeting">Reopen to correct</button>':''}</div></div><div class="table-wrap"><table><thead><tr><th>PARTICIPANT / BUSINESS</th><th>ASSIGNED MENTOR</th><th>ATTENDANCE FOR THIS MEETING</th><th></th></tr></thead><tbody>${sessionParticipants(s).map(p=>`<tr class="attendance-row ${s.marks[p.id]}"><td>${personCell(p)}</td><td>${esc(p.mentor)}</td><td>${editable?`<div class="attendance-buttons" aria-label="Attendance for ${esc(p.name)}">${[['present','Present'],['absent','Absent'],['unmarked','Not marked']].map(([value,label])=>`<button class="attendance-mark ${s.marks[p.id]===value?'selected '+value:''}" data-person="${p.id}" data-attendance-status="${value}" aria-pressed="${s.marks[p.id]===value}">${label}</button>`).join('')}</div>`:`<span class="attendance-status ${s.marks[p.id]}">${s.marks[p.id]==='present'?'Present':s.marks[p.id]==='absent'?'Absent':'Not marked'}</span>`}</td><td><button class="textbtn" data-profile="${p.id}">View profile</button></td></tr>`).join('')}</tbody></table></div><div class="disabled-note">${s.status==='draft'?'Live marks appear immediately in participant session histories. Finalize the complete register to include this meeting in attendance percentages and reports.':'This finalized register feeds each participant’s attendance total and the reporting summaries. Reopen it if you need to make a correction.'}</div></section>`;
}
function createMeetingForm() {
  if(state.role!=='mentor'||state.programme==='all'||state.cohort==='all')return;
  const sessions=meetingScope(),number=Math.max(0,...sessions.map(s=>s.number))+1;
  show(`${dialogHead('Create attendance meeting',`eKU ${esc(state.programme)} · Cohort ${esc(state.cohort)}`)}<div class="dialog-body"><form id="meeting-form" class="form-grid"><label>Meeting number<input name="number" type="number" min="1" max="999" step="1" required value="${number}"></label><label>Session date<input name="date" type="date" required value="${sessionDateToday()}"></label><label class="wide">Meeting title (optional)<input name="title" maxlength="100" placeholder="e.g. Digital marketing workshop"></label><div class="wide callout" style="margin:0">All current participants in this programme and cohort will appear on the register, including those assigned to other mentors. Everyone starts as “Not marked”.</div><div class="wide form-actions"><button class="secondary" type="button" data-close>Cancel</button><button class="primary" type="submit">Open attendance register</button></div></form></div>`);
}
function createMeeting(form) {
  if(state.role!=='mentor'||state.programme==='all'||state.cohort==='all')return;
  const f=new FormData(form),number=Number(f.get('number')),date=String(f.get('date')||''),title=String(f.get('title')||'').trim();
  if(!Number.isInteger(number)||number<1||number>999||!validSessionDate(date)||title.length>100){notify('Enter a valid meeting number and date.');return;}
  const existing=meetingScope().find(s=>s.number===number);
  if(existing){selectedMeetingId=existing.id;$('#dialog').close();render();notify('That meeting already exists. Its saved register is open.');return;}
  const roster=people.filter(p=>p.programme===state.programme&&p.cohort===state.cohort).map(p=>p.id);
  if(!roster.length){notify('Add participants to this programme and cohort first.');return;}
  const s={id:`meeting-${state.cohort}-${state.programme.replace(/ /g,'-')}-${number}`,programme:state.programme,cohort:state.cohort,number,date,title,status:'draft',roster,marks:Object.fromEntries(roster.map(id=>[id,'unmarked']))};
  attendanceStore.sessions.push(s);selectedMeetingId=s.id;ensureReportingMonth(date);
  const stored=saveAttendance();$('#dialog').close();render();if(stored)notify('Session register opened. Mark each participant’s attendance.');
}
function markAttendance(id,value) {
  const s=meetingScope().find(s=>s.id===selectedMeetingId);
  if(state.role!=='mentor'||!s||s.status!=='draft'||!s.roster.includes(id)||!['present','absent','unmarked'].includes(value))return;
  s.marks[id]=value;saveAttendance();render();
  document.querySelector(`button[data-person="${id}"][data-attendance-status="${value}"]`)?.focus();
}
function finalizeMeeting() {
  const s=meetingScope().find(s=>s.id===selectedMeetingId);if(state.role!=='mentor'||!s||s.status!=='draft')return;
  const k=sessionCounts(s);if(!k.total||k.unmarked){notify('Mark every participant as present or absent before finalizing.');return;}
  s.status='finalized';s.rosterFrozen=true;s.finalizedBy='Aina Rahman';s.updatedAt=new Date().toISOString();
  state.month=ensureReportingMonth(s.date);$('#month').value=String(state.month);
  const stored=saveAttendance();render();if(stored)notify('Attendance finalized. Participant totals and report figures are updated.');
}
function reopenMeeting() {
  const s=meetingScope().find(s=>s.id===selectedMeetingId);if(state.role!=='mentor'||!s||s.status!=='finalized')return;
  s.status='draft';const stored=saveAttendance();render();if(stored)notify('Register reopened. Its results are provisional until finalized again.');
}
function participantSessionHistory(p) {
  const a=participantAttendance(p),sessions=attendanceStore.sessions.filter(s=>s.roster.includes(p.id)).sort((a,b)=>b.date.localeCompare(a.date)||b.number-a.number);
  return `<div class="profile-summary">${stat('Finalized meeting attendance',a.total?`${a.present}/${a.total}`:'—',a.total?`${pct(a.present,a.total)}% attendance`:'No finalized meetings yet')}${stat('Milestones',p.milestones.filter(Boolean).length+'/4','Completion tracked by mentor')}${stat('Engagement',p.engagement==='Active'?'Active':'Follow-up','Mentor assessment')}</div><h3>Attendance by meeting</h3><div class="table-wrap"><table><thead><tr><th>MEETING / PROGRAMME</th><th>DATE</th><th>ATTENDANCE</th><th>REGISTER</th></tr></thead><tbody>${sessions.map(s=>`<tr><td>Meeting ${s.number}<small>eKU ${esc(s.programme)} · Cohort ${esc(s.cohort)}</small></td><td>${s.date}</td><td><span class="attendance-status ${s.marks[p.id]}">${s.marks[p.id]==='present'?'Present':s.marks[p.id]==='absent'?'Absent':'Not marked'}</span></td><td>${s.status==='finalized'?'Finalized':'Live draft'}</td></tr>`).join('')||'<tr><td colspan="4" class="empty">No meeting attendance has been recorded for this participant.</td></tr>'}</tbody></table></div><p class="note">Live draft marks appear here immediately. Only finalized meetings contribute to attendance percentages.</p><button class="secondary" data-open-register="${p.id}" style="margin:8px 0 24px">Open cohort attendance register</button>`;
}
function openParticipantRegister(id) {
  const p=people.find(p=>p.id===id);if(!p)return;
  state.programme=p.programme;state.cohort=p.cohort;$('#programme').value=p.programme;$('#cohort').value=p.cohort;selectedMeetingId='';navigate('attendance');
}
function resetAttendance() {attendanceStore.sessions.splice(0);attendanceStore.months=[...months];selectedMeetingId='';saveAttendance();}

document.addEventListener('click',e=>{
  const b=e.target.closest('button');if(!b)return;
  if(b.id==='new-meeting')createMeetingForm();
  if(b.dataset.attendanceStatus)markAttendance(b.dataset.person,b.dataset.attendanceStatus);
  if(b.id==='finalize-meeting')finalizeMeeting();
  if(b.id==='reopen-meeting')reopenMeeting();
  if(b.dataset.openRegister)openParticipantRegister(b.dataset.openRegister);
});
document.addEventListener('change',e=>{if(e.target.id==='meeting-select'){selectedMeetingId=e.target.value;render();}});
document.addEventListener('submit',e=>{if(e.target.id==='meeting-form'){e.preventDefault();createMeeting(e.target);}});
