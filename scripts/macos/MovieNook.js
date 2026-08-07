// Builds the macOS launcher at the MovieNook root. It derives the folder path
// from the app location, so the project can be moved without editing this file.
ObjC.import('Foundation');

const app = Application.currentApplication();
app.includeStandardAdditions = true;

function shellQuote(value) {
  return "'" + value.replace(/'/g, "'\\''") + "'";
}

const bundlePath = ObjC.unwrap($.NSBundle.mainBundle.bundlePath);
const rootDir = ObjC.unwrap($(bundlePath).stringByDeletingLastPathComponent);
const homeDir = ObjC.unwrap($.NSHomeDirectory());
const launcherScript = rootDir + '/MovieNook.sh';
const syncCredentialsScript = rootDir + '/scripts/portable/sync-credentials.sh';
const checkVpnScript = rootDir + '/scripts/portable/check-vpn.sh';
const logFile = rootDir + '/private/last-start.log';
const environment = 'export HOME=' + shellQuote(homeDir) + '; export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; ';

function safeNotify(message, title) {
  try {
    app.displayNotification(message, { withTitle: title });
  } catch (notificationError) {
    // Notification permissions must never control whether MovieNook starts.
  }
}

function appendLog(message) {
  try {
    const privateDir = rootDir + '/private';
    app.doShellScript('/bin/mkdir -p ' + shellQuote(privateDir));
    const entry = new Date().toISOString() + ' ' + String(message);
    app.doShellScript(
      '/usr/bin/printf ' + shellQuote('%s\n') + ' ' + shellQuote(entry) + ' >> ' + shellQuote(logFile)
    );
  } catch (loggingError) {
    // Logging must also remain non-critical.
  }
}

function installedApplicationPath(names) {
  for (const name of names) {
    const systemPath = '/Applications/' + name + '.app';
    const userPath = homeDir + '/Applications/' + name + '.app';
    if (app.doShellScript('[[ -d ' + shellQuote(systemPath) + ' ]] && echo yes || echo no').trim() === 'yes') {
      return systemPath;
    }
    if (app.doShellScript('[[ -d ' + shellQuote(userPath) + ' ]] && echo yes || echo no').trim() === 'yes') {
      return userPath;
    }
  }
  return '';
}

function rememberVpn(provider, authMethod) {
  app.doShellScript(
    environment +
    'MOVIENOOK_VPN_PROVIDER=' + shellQuote(provider) + ' ' +
    'MOVIENOOK_VPN_AUTH_METHOD=' + shellQuote(authMethod) + ' ' +
    '/bin/bash ' + shellQuote(syncCredentialsScript)
  );
}

let proceed = true;
let continueWithoutVpn = false;
let waitForVpnInBackground = false;
appendLog('MovieNook launcher started.');
try {
  app.doShellScript(environment + '/bin/bash ' + shellQuote(checkVpnScript));
  appendLog('An active VPN route was detected before startup.');
} catch (vpnError) {
  appendLog('No active VPN route was detected; opening the VPN chooser.');
  try {
    const nordPath = installedApplicationPath(['NordVPN']);
    const protonPath = installedApplicationPath(['ProtonVPN', 'Proton VPN']);
    const vpnOptions = [];
    if (nordPath) vpnOptions.push('NordVPN — installed');
    if (protonPath) vpnOptions.push('Proton VPN — installed (P2P requires a paid plan)');
    vpnOptions.push('Connect Another VPN Manually');
    vpnOptions.push('Continue Without VPN');

    const selected = app.chooseFromList(vpnOptions, {
      withPrompt: 'No active VPN route was detected. Choose a VPN to open and sign in, or explicitly continue without one.',
      defaultItems: vpnOptions.length > 1 ? [vpnOptions[0]] : ['Continue Without VPN'],
      okButtonName: 'Open Selected',
      cancelButtonName: 'Quit MovieNook',
      multipleSelectionsAllowed: false,
      emptySelectionAllowed: false
    });

    if (!selected) {
      appendLog('VPN chooser was cancelled.');
      proceed = false;
    } else if (selected[0] === 'Continue Without VPN') {
      rememberVpn('none', 'none');
      continueWithoutVpn = true;
      proceed = true;
    } else {
      let selectedVpnName = '';
      if (selected[0].startsWith('NordVPN')) {
        rememberVpn('nordvpn', 'native_app');
        app.doShellScript('/usr/bin/open ' + shellQuote(nordPath));
        selectedVpnName = 'NordVPN';
      } else if (selected[0].startsWith('Proton VPN')) {
        rememberVpn('protonvpn', 'native_app_oauth');
        // Opening the exact bundle path prevents macOS from handing this to an
        // iPhone/iPad copy or another application registered with a similar name.
        app.doShellScript('/usr/bin/open ' + shellQuote(protonPath));
        selectedVpnName = 'Proton VPN';
      } else if (selected[0] === 'Connect Another VPN Manually') {
        rememberVpn('custom', 'native_app');
        selectedVpnName = 'your VPN';
      }
      appendLog('Waiting for ' + selectedVpnName + ' to own the public route.');
      safeNotify('Sign in and connect. MovieNook will continue automatically.', 'MovieNook — waiting for ' + selectedVpnName);
      waitForVpnInBackground = true;
      proceed = true;
    }
  } catch (cancelled) {
    appendLog('VPN selection or waiting failed: ' + String(cancelled));
    proceed = false;
  }
}

if (proceed) try {
  const launchEnvironment = environment +
    (continueWithoutVpn ? 'export MOVIENOOK_CONTINUE_WITHOUT_VPN=1; ' : '') +
    (waitForVpnInBackground ? 'export MOVIENOOK_WAIT_FOR_VPN=1; ' : '');
  app.doShellScript(
    launchEnvironment + '/usr/bin/nohup /bin/bash ' + shellQuote(launcherScript) +
    ' >> ' + shellQuote(logFile) + ' 2>&1 < /dev/null &'
  );
  appendLog('MovieNook startup is continuing in the background.');
  safeNotify('Startup is continuing in the background. Plex and Seerr will open when ready.', 'MovieNook');
} catch (error) {
  app.displayDialog(
    'MovieNook could not start. Open private/last-start.log for details.\n\n' + error,
    { withTitle: 'MovieNook', buttons: ['OK'], defaultButton: 'OK', icon: 'stop' }
  );
}
