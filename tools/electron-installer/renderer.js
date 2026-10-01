const installRoot = document.getElementById('installRoot');
const pluginHome = document.getElementById('pluginHome');
const status = document.getElementById('status');
const output = document.getElementById('output');
const installButton = document.getElementById('install');
const uninstallButton = document.getElementById('uninstall');

function write(text) {
  output.textContent += text;
  output.scrollTop = output.scrollHeight;
}

function setBusy(value) {
  installButton.disabled = value;
  uninstallButton.disabled = value;
  document.querySelectorAll('input, [data-pick]').forEach((item) => { item.disabled = value; });
}

document.querySelectorAll('[data-pick]').forEach((button) => button.addEventListener('click', async () => {
  const selected = await window.sciInstaller.chooseDirectory();
  if (selected) document.getElementById(button.dataset.pick).value = selected;
}));

installButton.addEventListener('click', async () => {
  output.textContent = '';
  status.textContent = '正在安装…';
  setBusy(true);
  const result = await window.sciInstaller.install({ installRoot: installRoot.value, pluginHome: pluginHome.value });
  setBusy(false);
  status.textContent = result.code === 0 ? '安装完成。' : `安装失败（退出码 ${result.code}）。`;
  if (result.error) write(`${result.error}\n`);
});

uninstallButton.addEventListener('click', async () => {
  status.textContent = '正在卸载…';
  setBusy(true);
  const result = await window.sciInstaller.uninstall({ installRoot: installRoot.value, pluginHome: pluginHome.value });
  setBusy(false);
  status.textContent = result.cancelled ? '已取消。' : (result.code === 0 ? '卸载完成。' : `卸载失败（退出码 ${result.code}）。`);
  if (result.error) write(`${result.error}\n`);
});

window.sciInstaller.onOutput((message) => write(message.text));
window.sciInstaller.defaults().then((values) => {
  installRoot.value = values.installRoot;
  pluginHome.value = values.pluginHome;
});
