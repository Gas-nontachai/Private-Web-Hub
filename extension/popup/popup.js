const websites = [
  {
    name: "SerieDay",
    url: "https://www.serieday-z.com/",
    mark: "SD"
  },
  {
    name: "037HDD",
    url: "https://www.037-hdd.com/",
    mark: "037"
  },
  {
    name: "GoSeries4K",
    url: "https://www.goseries4k.com/",
    mark: "G4K"
  }
];

const siteList = document.querySelector("#site-list");

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
