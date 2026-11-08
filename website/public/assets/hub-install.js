// The Install button on /hub/install.
//
// ESP Web Tools' own button lists every serial port on the computer, then shows a menu (Install /
// Logs & Console), an erase checkbox and a confirm screen. This one lists only Espressif boards
// (the XIAO ESP32-C6's built-in USB) and goes straight to erasing and installing, then replaces the
// dialog's closing menu with our own next steps. It drives the install dialog from ESP Web Tools
// 10.4.0 (vendored and pinned in esp-web-tools/) through its internal _startInstall and
// _confirmInstall, so check those still exist when updating ESP Web Tools.
const DIALOG = "./esp-web-tools/install-dialog-im156JnI.js";
const MANIFEST = "/hub/firmware/manifest.json";
const ESPRESSIF_USB_VENDOR = 0x303a;

const root = document.getElementById("hub-install");
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function show(state) {
  for (const el of root.querySelectorAll("[data-state]")) el.hidden = el.dataset.state !== state;
}

async function waitFor(check, ms) {
  for (let waited = 0; waited < ms; waited += 50) {
    if (check()) return true;
    await sleep(50);
  }
  return check();
}

async function install() {
  let port;
  try {
    port = await navigator.serial.requestPort({ filters: [{ usbVendorId: ESPRESSIF_USB_VENDOR }] });
  } catch (error) {
    // Closed the picker, or the board wasn't listed.
    if (error.name === "NotFoundError") show("not-found");
    else alert(error.message);
    return;
  }
  try {
    // Only one attempt runs at a time (see `busy` below), so an open port is one a previous
    // attempt left open while the dialog was resetting the board.
    if (port.readable) await port.close().catch(() => {});
    await port.open({ baudRate: 115200, bufferSize: 8192 });
  } catch (error) {
    show("busy");
    return;
  }

  await import(DIALOG);
  const dialog = document.createElement("ewt-install-dialog");
  dialog.port = port;
  dialog.manifestPath = MANIFEST;
  let outcome = "ready";
  const closed = new Promise((resolve) => {
    dialog.addEventListener(
      "closed",
      () => {
        port.close().catch(() => {});
        show(outcome);
        resolve();
      },
      { once: true },
    );
  });
  document.body.appendChild(dialog);

  // The manifest sets new_install_improv_wait_time to 0, so the dialog only loads the manifest.
  const loaded = await waitFor(
    () => dialog._state === "ERROR" || (dialog._manifest && dialog._client === null),
    30000,
  );
  if (!loaded) {
    // Its Connecting screen has no close button, so give up on a download that hangs, close it
    // and offer a retry. If the download finishes later, the removed dialog does nothing with it.
    outcome = "offline";
    dialog._closeDialog();
    await closed;
    return;
  }
  if (dialog._state === "ERROR") {
    // The dialog shows what went wrong and closes when the user is done with it.
    await closed;
    return;
  }

  // Erase first, so every hub starts from the same clean state.
  dialog._startInstall(true);
  // Switching to INSTALL resets _installConfirmed when the dialog re-renders (willUpdate), so let
  // that update finish first; otherwise it flashes behind a confirm screen asking to install again.
  await dialog.updateComplete;
  dialog._confirmInstall();

  const installState = () => dialog._installState && dialog._installState.state;
  // Ends early if the user closes the dialog.
  let isClosed = false;
  closed.then(() => (isClosed = true));
  while (!isClosed && installState() !== "finished" && installState() !== "error") await sleep(100);
  if (installState() === "finished") {
    outcome = "done";
    // Let the dialog reopen the port after its reset, then close it and show our next steps.
    await waitFor(() => isClosed || dialog._client !== undefined, 5000);
    if (!isClosed) dialog._closeDialog();
  } else if (installState() === "error") {
    // Its error screen leads back to the menu, so close it and show our own tips instead, picked
    // by what went wrong: only a board that didn't answer needs install mode.
    const error = dialog._installState.details && dialog._installState.details.error;
    outcome =
      {
        failed_initialize: "failed",
        failed_firmware_download: "offline",
        not_supported: "wrong-board",
      }[error] || "interrupted";
    await sleep(300);
    if (!isClosed) dialog._closeDialog();
  }
  await closed;
}

if (!("serial" in navigator)) show("unsupported");
else if (!window.isSecureContext) show("not-allowed");
else {
  show("ready");
  // One attempt at a time: a second one on the same board would fight the first over its port.
  let busy = false;
  const buttons = root.querySelectorAll("button");
  for (const el of buttons) {
    el.addEventListener("click", async () => {
      if (busy) return;
      busy = true;
      for (const b of buttons) b.disabled = true;
      try {
        await install();
      } catch (error) {
        alert(error.message);
      } finally {
        busy = false;
        for (const b of buttons) b.disabled = false;
      }
    });
  }
}
