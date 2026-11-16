const status = document.getElementById("status");

document.getElementById("save").addEventListener("click", async () => {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  if (!tab?.url) {
    status.textContent = "No page to save.";
    return;
  }

  // The application id is ignored by Safari: the message always goes to this extension's own handler.
  const reply = await browser.runtime.sendNativeMessage("application.id", {
    action: "save",
    url: tab.url,
    title: tab.title ?? "",
  });

  status.textContent = reply?.ok ? `Saved — ${reply.count} bookmarks.` : `Failed: ${reply?.error ?? "unknown error"}`;
});
