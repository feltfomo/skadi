// a parse error here would stop Zen at an autoconfig dialog, so everything that can fail lives in
// the module, where a failure leaves the palette that userChrome.css imported at startup. system
// modules refuse file: URIs, which is why the store path gets a resource: name.
try {
  Services.io
    .getProtocolHandler("resource")
    .QueryInterface(Ci.nsIResProtocolHandler)
    .setSubstitution("skadi", Services.io.newURI("file://@modules@/modules/"));
  ChromeUtils.importESModule("resource://skadi/palette-reload.sys.mjs");
} catch (error) {
  Services.console.logStringMessage(`skadi: palette reload did not start: ${error}`);
}
