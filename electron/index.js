const {app, BrowserWindow, ipcMain, Menu, shell} = require('electron')
const sudo = require('sudo-prompt');
const {join} = require("node:path");
const {execSync} = require("child_process");
const {chmodSync, existsSync} = require("fs");
const options = {
    name: "DFU Tools",
    icns: join(__dirname, 'icon.icns')
}
const arch = process.arch === 'arm64' ? 'arm64' : 'x64';
let dfuTools = join(__dirname, `dfuTools_${arch}`)

if (__dirname.includes('/Contents/Resources/')) {
    dfuTools = join(__dirname, '../../dfuTools')
}
if (!existsSync(dfuTools)) {
    dfuTools = join(dfuTools, `dfuTools_${arch}`)
}

console.debug(`dfuTools: ${dfuTools}`)

chmodSync(dfuTools, '755', (err) => {
    if (err) throw err;
});

let configuratorStatus = false;
const createWindow = () => {
    const win = new BrowserWindow({
        width: 920,
        height: 580,
        minWidth: 920,
        minHeight: 580,
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false,
            webSecurity: true,
            devTools: true, // 如果是开发模式可以使用devTools 调试
            scrollBounce: process.platform === "darwin", // 在macos中启用橡皮动画
        },
        // transparent: true, //设置透明
    })

    win.loadFile(join(__dirname, 'index.html'))
    win.on('closed', () => {
        app.quit();
    });
    app.isPackaged && win.webContents.openDevTools()
}

Menu.setApplicationMenu(Menu.buildFromTemplate([{
    label: 'File',
    submenu: [
        {role: 'quit'},
        {role: 'close'},
    ]
}]));

app.whenReady().then(() => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
})

ipcMain.on('openReboot', (event) => {
    if (!checkConfiguratorRunning()) {
        event.returnValue = "configurator_not_running";
        return;
    }
    sudo.exec(`${dfuTools} reboot`, options, function (error, stdout, _stderr) {
        if (error) {
            console.debug(`error: ${error}`)
            event.returnValue = "run_error";
            return
        }
        event.returnValue = stdout;
    })
})

ipcMain.on('openDFU', (event) => {
    if (!checkConfiguratorRunning()) {
        console.debug(`configurator not running`)
        event.returnValue = "configurator_not_running";
        return;
    }
    sudo.exec(`${dfuTools} dfu`, options, function (error, stdout, _stderr) {
        if (error) {
            console.debug(`error: ${error}`)
            event.returnValue = "run_error";
            return
        }
        event.returnValue = stdout;
    })
})

ipcMain.on('openIPSW', (_event) => {
    const url = 'https://ipsw.me/product/Mac';
    shell.openExternal(url).then(() => {
        return "success"
    }).catch((err) => {
        return err
    })
})

ipcMain.on('openMDM', (_event) => {
    const url = 'http://mdms.fun';
    shell.openExternal(url).then(() => {
        return "success"
    }).catch((err) => {
        return err
    })
})

function checkConfiguratorRunning() {
    if (configuratorStatus) return true;
    const result = execSync('ps -ax | grep -v grep | grep com.apple.configurator; echo', {encoding: 'utf-8'}).toString().trim()
    configuratorStatus = result !== '';
    if (configuratorStatus) return true;
    try {
        execSync('open -a "Apple Configurator" >/dev/null 2>&1')
    } catch (e) {
        console.error(e)
    }
    return configuratorStatus;
}
