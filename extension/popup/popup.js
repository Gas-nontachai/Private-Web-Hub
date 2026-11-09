const siteList = document.querySelector("#site-list");
const updateButton = document.querySelector("#update-info");
const updateBadge = document.querySelector("#update-badge");
const RELEASES_API = "https://api.github.com/repos/Gas-nontachai/Private-Web-Hub/releases/latest";
const RELEASES_PAGE = "https://github.com/Gas-nontachai/Private-Web-Hub/releases/latest";

function compareVersions(a, b) {
  const left = a.split(".").map(Number);
  const right = b.split(".").map(Number);
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    const difference = (left[i] || 0) - (right[i] || 0);
    if (difference) return difference;
  }
  return 0;
}

async function checkForUpdate() {
  try {
    const response = await fetch(RELEASES_API, {
      headers: { Accept: "application/vnd.github+json" },
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) throw new Error(`Release check failed (${response.status})`);
    const release = await response.json();
    const match = typeof release.tag_name === "string"
      ? /^v(\d+\.\d+\.\d+)$/.exec(release.tag_name)
      : null;
    if (!match) throw new Error("Invalid release version");
    const installed = chrome.runtime.getManifest().version;
    const available = compareVersions(match[1], installed) > 0;
    updateBadge.hidden = !available;
    updateButton.title = available
      ? `มีเวอร์ชันใหม่ ${match[1]} — คลิกเพื่อดาวน์โหลด`
      : `เวอร์ชัน ${installed} — คลิกเพื่อตรวจสอบอีกครั้ง`;
    return available;
  } catch (_) {
    updateButton.title = "ตรวจสอบเวอร์ชันไม่ได้ — คลิกเพื่อลองอีกครั้ง";
    return null;
  }
}

updateButton.addEventListener("click", async () => {
  updateButton.disabled = true;
  updateButton.classList.add("checking");
  try {
    const available = await checkForUpdate();
    if (available) {
      chrome.tabs.create({ url: RELEASES_PAGE });
    } else if (available === false) {
      updateButton.title = "เป็นเวอร์ชันล่าสุดแล้ว";
    }
  } finally {
    updateButton.disabled = false;
    updateButton.classList.remove("checking");
  }
});

checkForUpdate();

for (const website of websites) {
  const url = new URL(website.url);
  const link = document.createElement("a");
  link.className = "site-link";
  link.href = url.href;
  link.target = "_blank";
  link.rel = "noopener noreferrer";

  const mark = document.createElement("span");
  mark.className = "site-mark";
  mark.setAttribute("aria-hidden", "true");
  mark.textContent = website.mark;

  const copy = document.createElement("span");
  copy.className = "site-copy";

  const name = document.createElement("span");
  name.className = "site-name";
  name.textContent = website.name;

  const host = document.createElement("span");
  host.className = "site-host";
  host.textContent = url.hostname;

  const arrow = document.createElement("span");
  arrow.className = "site-arrow";
  arrow.setAttribute("aria-hidden", "true");

  copy.append(name, host);
  link.append(mark, copy, arrow);
  siteList.append(link);
}
