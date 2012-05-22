
var Rain = (function () {

    var Util = {
        uuid4: function () {
            return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
                var r = Math.random()*16|0, v = c == 'x' ? r : (r&0x3|0x8);
                return v.toString(16);
            });
        },
        diffMatchPatch: new diff_match_patch(),
        log: function () {
            if (window.console && window.console.log) {
                console.log(Array.prototype.slice.call(arguments));
            }
        }
    };
    
    var Event = {
        INIT: 0,
        PUSH_PATCH: 1,
        PUSH_SNAPSHOT: 2
    };
    
    function RainEditor (options) {
        
        if (options.codeMirrorArgs == undefined) {
            options.codeMirrorArgs = {
                lineNumbers: true,
                fixedGutter: true
            };
        }
        
        options.diffInterval = 800;
        
        var codeMirror = CodeMirror.fromTextArea(
            document.getElementById(options.textAreaId),
            options.codeMirrorArgs
        );
        
        var serverSocket = new WebSocket(options.serverURL);
        
        var userId = Util.uuid4();
        
        var lastKnownValue = "";
        var diffInterval = null;
        
        var currentCursor, lineCount, newLineCount, patches, patched;

        this.save = function () {
            serverSocket.send("s"+JSON.stringify({
                event: Event.PUSH_SNAPSHOT,
                user: userId,
                data: codeMirror.getValue()
            }));
        };
        
        CodeMirror.commands.save = this.save;
        CodeMirror.modeURL = "/assets/cm/mode/%N/%N.js"; // TODO make configurable
        
        $('#modeSelect').change(function (e) {
            codeMirror.setOption("mode", e.target.value);
            CodeMirror.autoLoadMode(codeMirror, e.target.value);
        });
        
        function computeAndSendPatches() {
            var currentValue = codeMirror.getValue();
            patches = Util.diffMatchPatch.patch_make(lastKnownValue, currentValue);
            
            if (patches.length) {
                serverSocket.send(JSON.stringify({
                    event: Event.PUSH_PATCH,
                    user: userId,
                    data: Util.diffMatchPatch.patch_toText(patches)
                }));
            }
            
            lastKnownValue = currentValue;
        }
        
        function setEditorValue(newValue) {
            currentCursor = codeMirror.getCursor();
                            
            lineCount = codeMirror.lineCount();
            codeMirror.setValue(newValue);
            newLineCount = codeMirror.lineCount();
            // TODO: Update for same line editing too based on line lengths?
            if (newLineCount < lineCount) {
                currentCursor.line -= (lineCount - newLineCount);
            }
            else if (newLineCount > lineCount) {
                currentCursor.line += (newLineCount - lineCount);
            }
            codeMirror.setCursor(currentCursor);
            
            lastKnownValue = newValue;
        }
        
        var diffFn = function () {
            computeAndSendPatches();
        };
        
        function startDiffing() {
            if (diffInterval == null) {
                diffInterval = setInterval(diffFn, options.diffInterval);
            }
        }
        
        function stopDiffing() {
            if (diffInterval != null) {
                clearInterval(diffInterval);
                diffInterval = null;
            }
        }
        
        serverSocket.onmessage = function (message) {
            message = JSON.parse(message.data);
            
            if (message.user != userId) {
                stopDiffing();
                
                switch (message.event) {
                    case Event.INIT:
                        lastKnownValue = JSON.parse(message.snapshot).data;
                        var patch;
                        for (var i = 0; i < message.patchList.length; i++) {
                            patch = JSON.parse(message.patchList[i]);
                            patched = Util.diffMatchPatch.patch_apply(
                                Util.diffMatchPatch.patch_fromText(patch.data),
                                lastKnownValue
                            );
                            lastKnownValue = patched[0];
                        }
                        codeMirror.setValue(lastKnownValue);
                        break;
                    case Event.PUSH_SNAPSHOT:
                        lastKnownValue = codeMirror.getValue();
                        patches = Util.diffMatchPatch.patch_make(lastKnownValue, message.data); // TODO: is this back to front? - No, want to update your state (if you're behind the times?!)
                        patched = Util.diffMatchPatch.patch_apply(patches, lastKnownValue);
                        setEditorValue(patched[0]);
                        break;
                    case Event.PUSH_PATCH:
                        computeAndSendPatches();
                        patched = Util.diffMatchPatch.patch_apply(
                            Util.diffMatchPatch.patch_fromText(message.data),
                            codeMirror.getValue()
                        );
                        setEditorValue(patched[0]);
                        break;
                }
                
                startDiffing();
            }
        };
        
        serverSocket.onerror = function () {
            Util.log("Socket error!");
        };
        
    };
    
    return RainEditor;

}());