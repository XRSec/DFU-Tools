const {app, BrowserWindow, ipcMain, Menu, shell} = require('electron')
const {join} = require("node:path");
const {execSync, exec} = require("child_process");
const {chmod, existsSync, lstatSync} = require("fs");
const prompt = require('electron-prompt');

const arch = process.arch === 'arm64' ? 'arm64' : 'x64';
let dfuTools = join(__dirname, `dfuTools/${arch}/dfuTools`),
    admin_pass = '',
    configuratorStatus = false,
    win;

if (__dirname.includes('/Contents/Resources/')) {
    dfuTools = join(__dirname, `../../dfuTools`)
}

console.debug(`dfuTools: ${dfuTools}`)

chmod(dfuTools, '755', (err) => {
    if (err) {
        throw err;
    } else {
        console.debug(`dfuTools chmod success`)
    }
});

const createWindow = () => {
    win = new BrowserWindow({
        width: 920,
        height: 580,
        minWidth: 920,
        minHeight: 580,
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false,
            webSecurity: true,
            devTools: !app.isPackaged || process.env.DFU_DEBUG, // 如果是开发模式可以使用devTools 调试
            scrollBounce: process.platform === "darwin", // 在macos中启用橡皮动画
        },
        // transparent: true, //设置透明
    })

    win.loadFile(join(__dirname, 'index.html'))
    win.on('closed', () => {
        app.quit();
    });
    (!app.isPackaged || process.env.DFU_DEBUG) && win.webContents.openDevTools()
    win.webContents.on('dom-ready', () => {
        if (admin_pass !== "") return;

        function testPrivilege() {
            exec(`echo '${admin_pass}' | sudo -S whoami`, {encoding: 'utf-8'}).on('exit', (code) => {
                (code !== 0) && getPassword();
                console.debug('run as admin privilege')
            }).on('error', (err) => {
                console.debug(err)
                getPassword();
            })
        }

        function getPassword() {
            prompt({
                title: '提示',
                label: '请输入您的密码 / Please Enter U Passwd',
                value: '',
                inputAttrs: {type: 'password'},
                type: 'input'
            }).then((r) => {
                if (r === null) {
                    console.debug('user cancelled');
                } else {
                    console.debug('pass:', r);
                    admin_pass = r;
                    testPrivilege();
                }
            }).catch(console.error);
        }

        getPassword()
    })
}

Menu.setApplicationMenu(Menu.buildFromTemplate(
    [{
        label: 'File',
        submenu: [
            {role: 'quit'},
            {role: 'close'},
            {
                label: 'Toggle Developer Tools',
                click: () => {
                    win.webContents.toggleDevTools();
                }
            }]
    }]
));

app.whenReady().then(() => {
    if (BrowserWindow.getAllWindows().length === 0) {
        createWindow();
    }
})

ipcMain.on('openReboot', (event) => {
    if (!checkConfiguratorRunning()) {
        event.returnValue = "configurator_not_running";
        return;
    }
    exec(`echo '${admin_pass}' | sudo -S ${dfuTools} reboot`, {encoding: 'utf-8'}, function (_error, stdout, _stderr) {
        if (stdout?.includes('No connection detected')) {
            event.returnValue = "no_connection";
            return;
        } else if (stdout?.includes('IOCreatePlugInInterfaceForService failed')) {
            event.returnValue = "no_admin_permission";
            return;
        } else if (_error?.toString().includes('command not found')) {
            event.returnValue = "no_dfu_permission";
            return;
        }
        console.debug(`error: ${_error} stderr: ${_stderr}`)
        event.returnValue = stdout;
    })
})

ipcMain.on('openDFU', (event) => {
    if (!checkConfiguratorRunning()) {
        console.debug(`configurator not running`)
        event.returnValue = "configurator_not_running";
        return;
    }
    exec(`echo '${admin_pass}' | sudo -S ${dfuTools} dfu`, {encoding: 'utf-8'}, function (_error, stdout, _stderr) {
        console.log(_error)
        if (stdout?.includes('No connection detected')) {
            event.returnValue = "no_connection";
            return;
        } else if (stdout?.includes('IOCreatePlugInInterfaceForService failed')) {
            event.returnValue = "no_admin_permission";
            return;
        } else if (_error?.toString().includes('command not found')) {
            event.returnValue = "no_dfu_permission";
            return;
        }
        console.debug(`error: ${_error} stderr: ${_stderr}`)
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
