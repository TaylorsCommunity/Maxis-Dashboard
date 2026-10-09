// Local-only participant records, forms, photo placeholders and report downloads.
// No database, real authentication or network uploads are used by this prototype.
const STORAGE_KEY = 'maxis-impact-prototype-v2';
let photoReadVersion = 0;

function loadParticipants() {
  const seed = () => JSON.parse(JSON.stringify(demoPeople));
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (!saved) return seed();
    const data = JSON.parse(saved);
    if (!Array.isArray(data) || data.length > 1000) return seed();
    const ids = new Set();
    const valid = data.every(p => {
      if (!p || typeof p.name !== 'string' || typeof p.business !== 'string' ||
          !/^EKU-\d{3,}$/.test(p.id) || ids.has(p.id) ||
          !['Aina Rahman', 'Daniel Lee'].includes(p.mentor) ||
          !['01', '02'].includes(p.cohort) ||
          !['Accelerator', 'Digital Marketing'].includes(p.programme) ||
          !Array.isArray(p.monthly) || p.monthly.length < 3 || p.monthly.length > 120 ||
          !Array.isArray(p.attendance) || p.attendance.length < 3 || p.attendance.length > 120 ||
          !p.attendance.every((n,i) => Number.isInteger(n) && n >= 0 && n <= (i + 1) * 4) ||
          !Array.isArray(p.milestones) || p.milestones.length !== 4 ||
          !p.milestones.every(n => typeof n === 'boolean') || !Array.isArray(p.log) ||
          !Number.isFinite(p.progress) || p.progress < 0 || p.progress > 100 ||
          !['Active','Follow-up needed'].includes(p.engagement) ||
          !(p.baseline === null || Number.isFinite(p.baseline)) ||
          !p.monthly.every(d => !d || Number.isFinite(d.sales) && d.sales >= 0 && Number.isFinite(d.cost) && d.cost >= 0 && ['Self-reported','Mentor reviewed'].includes(d.evidence))) return false;
      ids.add(p.id);
      if (p.photo && !/^data:image\/(jpeg|png|webp);base64,/.test(p.photo)) p.photo = '';
      return true;
    });
    return valid ? data : seed();
  } catch { return seed(); }
}

function saveLocal() {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(people)); return true; }
  catch {
    notify('Browser storage is full or unavailable. These changes will last only until you reload.');
    return false;
  }
}

function participantForm(id = '') {
  if (state.role !== 'mentor') return;
  const participant = id ? people.find(p => p.id === id && p.mentor === 'Aina Rahman') : null;
  if (id && !participant) return;
  photoReadVersion++;
  pendingPhoto = participant?.photo || '';
  const value = key => esc(participant?.[key] ?? '');
  const option = (value, selected, label = value) => `<option value="${esc(value)}" ${value === selected ? 'selected' : ''}>${esc(label)}</option>`;
  show(`${dialogHead(participant ? 'Edit participant details' : 'Add new participant', 'Create a beneficiary record. Participants do not receive login accounts.')}
    <div class="dialog-body"><form id="participant-form" data-id="${id}" class="form-grid">
      <div class="wide new-photo-row"><div id="draft-photo-preview" class="photo-placeholder">${pendingPhoto ? `<img src="${esc(pendingPhoto)}" alt="Selected participant photo">` : '<span>No photo</span>'}</div>
        <div><label class="upload-button" for="new-photo-input">${pendingPhoto ? 'Change photo' : 'Choose photo'}</label><input class="file-input" id="new-photo-input" type="file" accept="image/png,image/jpeg,image/webp"><p class="note">Optional. JPG, PNG or WebP, up to 2 MB. Stored in this browser only.</p></div></div>
      <label>Full name<input name="name" maxlength="80" required value="${value('name')}" placeholder="Participant’s name"></label>
      <label>Business name<input name="business" maxlength="100" required value="${value('business')}" placeholder="Business / trading name"></label>
      <label>Programme<select name="programme">${['Accelerator','Digital Marketing'].map(v=>option(v,participant?.programme || (state.programme === 'all' ? 'Accelerator' : state.programme),'eKU '+v)).join('')}</select></label>
      <label>Cohort<select name="cohort">${option('01',participant?.cohort || (state.cohort === 'all' ? '01' : state.cohort),'Cohort 01 · Selangor')}${option('02',participant?.cohort || state.cohort,'Cohort 02 · Kuala Lumpur')}</select></label>
      <label>Business sector<select name="sector">${['F&B','Retail','Services','Fashion','Arts & craft','Other'].map(v=>option(v,participant?.sector || 'F&B')).join('')}</select></label>
      <label>Location<input name="city" maxlength="80" value="${value('city')}" placeholder="City / state"></label>
      <label>Age<input name="age" type="number" min="18" max="100" step="1" value="${value('age')}" placeholder="Optional"></label>
      <label>Gender<select name="gender">${['Not specified','Female','Male','Other'].map(v=>option(v,participant?.gender || 'Not specified')).join('')}</select></label>
      <label>Participant background<select name="background">${['Not specified','B40','Asnaf','PWD','Other'].map(v=>option(v,participant?.background || 'Not specified')).join('')}</select></label>
      <label>Assigned mentor<input value="Aina Rahman" disabled><small>New records are assigned to the current mentor preview.</small></label>
      <label>Email (optional)<input name="email" type="email" maxlength="120" value="${value('email')}" placeholder="Demo email"></label>
      <label>Phone (optional)<input name="phone" type="tel" maxlength="30" value="${value('phone')}" placeholder="Demo phone"></label>
      <div class="wide form-section"><h3>Baseline business performance</h3><p>Optional. Enter both values to calculate baseline monthly net income. Leave both blank when not collected.</p></div>
      <label>Baseline monthly sales (RM)<input name="baselineSales" type="number" min="0" max="10000000" step="0.01" value="${value('baselineSales')}" placeholder="Not collected"></label>
      <label>Baseline monthly operating costs (RM)<input name="baselineCost" type="number" min="0" max="10000000" step="0.01" value="${value('baselineCost')}" placeholder="Not collected"></label>
      <label class="wide">Business goal / profile notes<textarea name="goal" maxlength="1500" rows="3" placeholder="What does this participant want to achieve?">${value('goal')}</textarea></label>
      <div class="wide callout" style="margin-top:0">Save the profile, then add monthly check-ins for sales, costs, progress and story updates. Take attendance in the session register. No financial outcomes are invented for new participants.</div>
      <div class="wide form-actions"><button type="button" class="secondary" ${id?`data-profile="${id}"`:'data-close'}>Cancel</button><button type="submit" class="primary">${id?'Save participant details':'Create participant'}</button></div>
    </form></div>`);
}

function saveParticipant(form) {
  if (state.role !== 'mentor') return;
  const id = form.dataset.id;
  const original = id ? people.find(p=>p.id === id && p.mentor === 'Aina Rahman') : null;
  if (id && !original) return;
  const f = new FormData(form), get = key => String(f.get(key) ?? '').trim();
  const name = get('name'), business = get('business');
  if (!name || !business || name.length > 80 || business.length > 100) { notify('Enter a participant name and business name.'); return; }
  const rawSales = get('baselineSales'), rawCost = get('baselineCost');
  if (Boolean(rawSales) !== Boolean(rawCost)) { notify('Enter both baseline sales and costs, or leave both blank.'); return; }
  const baselineSales = rawSales ? Number(rawSales) : null, baselineCost = rawCost ? Number(rawCost) : null;
  if ((rawSales && (!Number.isFinite(baselineSales) || baselineSales < 0 || baselineSales > 10000000)) || (rawCost && (!Number.isFinite(baselineCost) || baselineCost < 0 || baselineCost > 10000000))) { notify('Enter valid non-negative baseline values.'); return; }
  const age = get('age') ? Number(get('age')) : null;
  if (age !== null && (!Number.isInteger(age) || age < 18 || age > 100)) { notify('Enter an age between 18 and 100, or leave it blank.'); return; }
  const programme = get('programme'), cohort = get('cohort'), gender=get('gender'), background=get('background'), sector=get('sector');
  if (!['Accelerator','Digital Marketing'].includes(programme) || !['01','02'].includes(cohort) || !['Not specified','Female','Male','Other'].includes(gender) || !['Not specified','B40','Asnaf','PWD','Other'].includes(background) || !['F&B','Retail','Services','Fashion','Arts & craft','Other'].includes(sector)) return;
  const patch = {name,business,initials:name.split(/\s+/).slice(0,2).map(v=>v[0]).join('').toUpperCase(),programme,cohort,gender,background,sector,age,city:get('city'),email:get('email'),phone:get('phone'),goal:get('goal'),baselineSales,baselineCost,baseline:baselineSales===null?null:baselineSales-baselineCost,photo:pendingPhoto || ''};
  let p;
  if (original) { Object.assign(original,patch);original.milestones[0]=patch.baseline!==null; p=original; }
  else {
    const number = Math.max(0,...people.map(p=>Number(p.id.split('-')[1])))+1;
    p = {id:'EKU-'+String(number).padStart(3,'0'), ...patch, mentor:'Aina Rahman',monthly:months.map(()=>null),attendance:months.map(()=>0),progress:0,engagement:'Active',storyConsent:false,story:'',milestones:[patch.baseline!==null,false,false,false],log:[]};
    people.push(p);
  }
  // Make a newly created/moved profile visible even if previous filters exclude it.
  state.cohort='all';state.programme='all';state.query='';state.page='beneficiaries';
  $('#cohort').value='all';$('#programme').value='all';
  const stored=saveLocal();render();profile(p.id);
  if(stored) notify(original?'Participant details saved.':'Participant created. Add a monthly check-in to track their progress.');
}

function photoArea(p,editable) {
  return `<div class="profile-photo-block"><div class="photo-placeholder">${p.photo?`<img src="${esc(p.photo)}" alt="${esc(p.name)} participant photo">`:'<span>No photo</span>'}</div>${editable?`<label class="photo-upload-link" for="participant-photo-input">${p.photo?'Change photo':'Upload photo'}</label><input class="file-input" id="participant-photo-input" data-id="${p.id}" type="file" accept="image/png,image/jpeg,image/webp">${p.photo?`<button class="textbtn photo-remove" data-remove-photo="${p.id}">Remove photo</button>`:''}`:''}</div>`;
}

function fileToPhoto(file) {
  return new Promise((resolve,reject)=>{
    if (!file) return reject(Error('No file selected.'));
    if (!['image/jpeg','image/png','image/webp'].includes(file.type)) return reject(Error('Choose a JPG, PNG or WebP image.'));
    if (file.size > 2*1024*1024) return reject(Error('Choose an image smaller than 2 MB.'));
    const reader=new FileReader();
    reader.onerror=()=>reject(Error('The image could not be read.'));
    reader.onload=()=>{
      const img=new Image();
      img.onerror=()=>reject(Error('This image could not be opened.'));
      img.onload=()=>{
        try {
          const scale=Math.min(1,600/Math.max(img.width,img.height));
          const canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(img.width*scale));canvas.height=Math.max(1,Math.round(img.height*scale));
          const ctx=canvas.getContext('2d');ctx.fillStyle='#ffffff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(img,0,0,canvas.width,canvas.height);
          resolve(canvas.toDataURL('image/jpeg',0.82));
        } catch { reject(Error('The image could not be prepared.')); }
      };
      img.src=reader.result;
    };
    reader.readAsDataURL(file);
  });
}

async function readPhoto(file,id) {
  if(!file||state.role!=='mentor') return;
  const p=people.find(p=>p.id===id && p.mentor==='Aina Rahman');if(!p)return;
  try { const photo=await fileToPhoto(file);if(state.role!=='mentor')return;p.photo=photo;const stored=saveLocal();render();profile(id,state.tab);if(stored)notify('Participant photo saved locally.'); }
  catch(err){notify(err.message);}
}

async function readDraftPhoto(file) {
  if(!file||state.role!=='mentor') return;
  const version=photoReadVersion;
  const submit=document.querySelector('#participant-form button[type=submit]');
  if(submit)submit.disabled=true;
  try {const photo=await fileToPhoto(file);if(version!==photoReadVersion||!$('#participant-form')||state.role!=='mentor')return;pendingPhoto=photo;$('#draft-photo-preview').innerHTML=`<img src="${esc(photo)}" alt="Selected participant photo">`;}
  catch(err){notify(err.message);}
  finally{if(submit)submit.disabled=false;}
}

function removePhoto(id) {
  if(state.role!=='mentor') return;
  const p=people.find(p=>p.id===id&&p.mentor==='Aina Rahman');if(!p)return;
  p.photo='';const stored=saveLocal();render();profile(id,state.tab);if(stored)notify('Participant photo removed.');
}

function resetDemo() {
  show(`${dialogHead('Reset prototype records','This will remove locally added participants, edits and uploaded photos.')}
    <div class="dialog-body"><p>Restore the original fictional demo records in this browser?</p><div class="form-actions"><button class="secondary" data-close>Cancel</button><button class="primary" id="confirm-reset">Restore demo records</button></div></div>`);
}
document.addEventListener('click',event=>{
  if(event.target.closest('button')?.id!=='confirm-reset')return;
  people.splice(0,people.length,...JSON.parse(JSON.stringify(demoPeople)));
  resetAttendance();initializeAttendance();
  const stored=saveLocal();navigate('overview');if(stored)notify('Original demo records restored.');
});

function exportHtml() {
  const reportCss=`*{box-sizing:border-box}body{font:15px/1.6 Arial,sans-serif;color:#1d2c26;background:white;padding:35px;max-width:1100px;margin:auto}h2{font-size:24px}h3{margin-top:25px}p,.note{color:#66756e}.report-brand{font-size:35px;font-weight:700;color:#178d38}.eyebrow{color:#178d38;font-size:12px}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:20px 0}.stat{border:1px solid #e3eae5;padding:16px;border-radius:8px}.stat-label,.stat-sub{font-size:12px;color:#66756e}.stat-value{font-size:26px;font-weight:bold;margin:8px 0}.callout{padding:15px;background:#ecf6ed;border-left:3px solid #178d38}.detail-line{display:flex;justify-content:space-between;border-bottom:1px solid #e3eae5;padding:10px 0;gap:20px}.chart{max-width:650px;width:100%;display:block}.chart text{font-family:Arial;font-size:12px;fill:#66756e}.legend{display:flex;gap:20px;font-size:12px}.note{font-size:12px}@media(max-width:600px){.stats{grid-template-columns:1fr 1fr}body{padding:15px}}@media print{body{padding:0}}`;
  download(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Maxis Prototype Monthly Impact Brief</title><style>${reportCss}</style></head><body>${reportHtml()}</body></html>`,'Maxis_Prototype_Monthly_Impact_Brief.html','text/html');
  notify('Monthly report downloaded.');
}

function csvValue(value) {
  const text=String(value??'');
  return typeof value==='string' && /^[=+@\-]/.test(text) ? "'"+text : text;
}
