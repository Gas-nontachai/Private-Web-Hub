const master = document.querySelector('#adguard-enabled');
const site = document.querySelector('#adguard-site');
const hostLabel = document.querySelector('#adguard-host');
const status = document.querySelector('#adguard-status');
const reload = document.querySelector('#adguard-reload');
let current;
function render(value) {
  current=value;
  master.checked=value.settings?.enabled ?? true;
  master.disabled=!!value.error;
  site.checked=!!value.host && !value.settings?.disabledHosts.includes(value.host);
  site.disabled=!!value.error || !value.host || !master.checked;
  hostLabel.textContent=value.host || 'เปิดหน้าเว็บ HTTP/HTTPS เพื่อตั้งค่ารายเว็บ';
  status.textContent=value.error ? `AdGuard ไม่พร้อม: ${value.error}` : `Base · Tracking Protection · Mobile Ads (${value.rules.toLocaleString()} กฎ)`;
}
async function update(key,value) {
  master.disabled=true;site.disabled=true;
  status.textContent='กำลังบันทึก…';
  try {
    const response=await chrome.runtime.sendMessage({type:'MOVIE_ADGUARD_SET',key,value,host:current?.host});
    if (!response.settings) throw new Error(response.error || 'บันทึกไม่สำเร็จ');
    render(response);reload.hidden=false;
    status.textContent='บันทึกแล้ว · โหลดหน้าใหม่เพื่อใช้ค่าครบทุกส่วน';
  } catch (error) {status.textContent=error.message;master.disabled=false;site.disabled=!current?.host;}
}
master.addEventListener('change',()=>update('enabled',master.checked));
site.addEventListener('change',()=>update('siteEnabled',site.checked));
reload.addEventListener('click',async()=>{
  const [tab]=await chrome.tabs.query({active:true,currentWindow:true});
  if (tab?.id) await chrome.tabs.reload(tab.id);
  window.close();
});
chrome.runtime.sendMessage({type:'MOVIE_ADGUARD_STATE'}).then(render).catch(error=>{status.textContent=`AdGuard ไม่พร้อม: ${error.message}`;});
