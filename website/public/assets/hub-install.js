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
    if (!port.readable) await port.open({ baudRate: 115200, bufferSize: 8192 });
  } catch (error) {
    show("busy");
    return;
  }

  await import(DIALOG);
  const dialog = document.createElement("ewt-install-dialog");
  dialog.port = port;
  dialog.manifestPath = MANIFEST;
  let finished = false;
  let failed = false;
  dialog.addEventListener(
    "closed",
    () => {
      port.close().catch(() => {});
      show(finished ? "done" : failed ? "failed" : "ready");
    },
    { once: true },
  );
  document.body.appendChild(dialog);

  // The manifest sets new_install_improv_wait_time to 0, so the dialog only loads the manifest.
  await waitFor(() => dialog._state === "ERROR" || (dialog._manifest && dialog._client === null), 10000);
  if (dialog._state === "ERROR" || !dialog._manifest) return; // the dialog shows what went wrong

  // Erase first, so every hub starts from the same clean state.
  dialog._startInstall(true);
  dialog._confirmInstall();

  await waitFor(() => {
    const state = dialog._installState && dialog._installState.state;
    return state === "finished" || state === "error";
  }, 10 * 60 * 1000);
  if (dialog._installState && dialog._installState.state === "finished") {
    finished = true;
    // Let the dialog reopen the port after its reset, then close it and show our next steps.
    await waitFor(() => dialog._client !== undefined, 5000);
    dialog._closeDialog();
  } else {
    // Its error screen leads back to the menu, so close it and show our own tips instead.
    failed = true;
    await sleep(300);
    dialog._closeDialog();
  }
}

if (!("serial" in navigator)) show("unsupported");
else if (!window.isSecureContext) show("not-allowed");
else {
  show("ready");
  for (const el of root.querySelectorAll("button")) {
    el.addEventListener("click", () => {
      install().catch((error) => alert(error.message));
    });
  }
}
